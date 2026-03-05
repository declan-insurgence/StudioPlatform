[CmdletBinding()]
param(
    [string]$BaseUrl = "http://127.0.0.1:8787",
    [string]$SessionId = "demo-session",
    [int]$StartupTimeoutSeconds = 120,
    [switch]$SkipInstall,
    [switch]$KeepRunning
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }

    Write-Host "PASS: $Message" -ForegroundColor Green
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [string[]]$Arguments = @()
    )

    & $FilePath @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $argsText = if ($Arguments.Count -gt 0) { " $($Arguments -join ' ')" } else { "" }
        throw "Command failed with exit code ${exitCode}: $FilePath$argsText"
    }
}

function Invoke-JsonRpc {
    param(
        [Parameter(Mandatory)] [string]$Method,
        [hashtable]$Params,
        [string]$Id = [guid]::NewGuid().ToString()
    )

    $payload = @{
        jsonrpc = "2.0"
        id      = $Id
        method  = $Method
    }

    if ($null -ne $Params) {
        $payload.params = $Params
    }

    $jsonBody = $payload | ConvertTo-Json -Depth 10

    return Invoke-RestMethod -Uri "$BaseUrl/mcp" -Method Post -Headers @{ "x-session-id" = $SessionId } -ContentType "application/json" -Body $jsonBody
}

function Get-AvailableLogPath {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path $Path)) {
        return $Path
    }

    try {
        Remove-Item $Path -Force -ErrorAction Stop
        return $Path
    }
    catch {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $directory = Split-Path -Parent $Path
        $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        $extension = [System.IO.Path]::GetExtension($Path)
        $fallback = Join-Path $directory "$name.$timestamp$extension"
        Write-Host "WARN: Could not clear existing log '$Path'. Using '$fallback'." -ForegroundColor Yellow
        return $fallback
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$logDir = Join-Path $repoRoot ".tmp"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$stdoutLog = Join-Path $logDir "wrangler-dev.stdout.log"
$stderrLog = Join-Path $logDir "wrangler-dev.stderr.log"

$devProcess = $null
$locationPushed = $false
$pnpmExecutable = "pnpm"
$isWindowsPowerShellDesktop = $PSVersionTable.PSEdition -eq "Desktop"
$existingWranglerDevPids = @()

try {
    Write-Step "Validating prerequisites"
    $required = @("node", "pnpm")
    foreach ($cmd in $required) {
        $exists = Get-Command $cmd -ErrorAction SilentlyContinue
        Assert-True ($null -ne $exists) "$cmd is available"
    }

    if ($env:OS -eq "Windows_NT") {
        $pnpmCmd = Get-Command "pnpm.cmd" -ErrorAction SilentlyContinue
        if ($null -ne $pnpmCmd) {
            $pnpmExecutable = $pnpmCmd.Source
        }

        $existingWranglerDevPids = @(
            Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine -match "wrangler dev" } |
            Select-Object -ExpandProperty ProcessId
        )
    }

    Push-Location $repoRoot
    $locationPushed = $true

    if (-not $SkipInstall) {
        Write-Step "Installing dependencies"
        Invoke-NativeCommand -FilePath $pnpmExecutable -Arguments @("install", "--frozen-lockfile")
        Invoke-NativeCommand -FilePath $pnpmExecutable -Arguments @("--dir", "widget", "install", "--frozen-lockfile")
    }

    Write-Step "Building widget assets"
    Invoke-NativeCommand -FilePath $pnpmExecutable -Arguments @("--dir", "widget", "build")

    Write-Step "Starting worker locally (pnpm dev)"
    $stdoutLog = Get-AvailableLogPath -Path $stdoutLog
    $stderrLog = Get-AvailableLogPath -Path $stderrLog

    $devProcess = Start-Process -FilePath $pnpmExecutable -ArgumentList "dev" -WorkingDirectory $repoRoot -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -PassThru
    Assert-True (-not $devProcess.HasExited) "wrangler dev process started"

    Write-Step "Waiting for /health to become ready"
    $deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 750
        try {
            $healthRequestParams = @{
                Uri = "$BaseUrl/health"
                Method = "Get"
                TimeoutSec = 2
            }
            if ($isWindowsPowerShellDesktop) {
                $healthRequestParams.UseBasicParsing = $true
            }
            $health = Invoke-WebRequest @healthRequestParams
            if ($health.StatusCode -eq 200 -and $health.Content.Trim() -eq "ok") {
                $ready = $true
                break
            }
        }
        catch {
            # keep polling while booting
        }

        if ($devProcess.HasExited) {
            throw "wrangler dev exited early. Check logs: $stdoutLog and $stderrLog"
        }
    }
    Assert-True $ready "worker health endpoint is ready"

    Write-Step "Testing root endpoint contract"
    $root = Invoke-RestMethod -Uri "$BaseUrl/" -Method Get
    Assert-True ($root.name -eq "Studio Platform MCP Worker") "root endpoint returns worker name"
    Assert-True ($root.connect.sse -eq "$BaseUrl/sse") "root endpoint advertises SSE URL"
    Assert-True ($root.connect.streamableHttp -eq "$BaseUrl/mcp") "root endpoint advertises MCP URL"

    Write-Step "Testing SSE endpoint headers"
    if (-not ("System.Net.Http.HttpClient" -as [type])) {
        Add-Type -AssemblyName "System.Net.Http"
    }
    $httpClient = [System.Net.Http.HttpClient]::new()
    $request = $null
    $response = $null
    try {
        $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, "$BaseUrl/sse")
        $request.Headers.Add("x-session-id", $SessionId)
        $sendTask = $httpClient.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead)
        $sendTask.Wait()
        $response = $sendTask.Result
        Assert-True ($response.IsSuccessStatusCode) "SSE endpoint returns success status"
        Assert-True ($response.Content.Headers.ContentType.MediaType -eq "text/event-stream") "SSE endpoint returns text/event-stream"
    }
    finally {
        if ($null -ne $response) { $response.Dispose() }
        if ($null -ne $request) { $request.Dispose() }
        $httpClient.Dispose()
    }

    Write-Step "Testing MCP initialize"
    $initialize = Invoke-JsonRpc -Method "initialize"
    Assert-True ($initialize.result.serverInfo.name -eq "studio-platform-mcp") "initialize returns MCP server name"

    Write-Step "Testing tools/list"
    $toolsList = Invoke-JsonRpc -Method "tools/list"
    $toolNames = @($toolsList.result.tools | ForEach-Object { $_.name })
    Assert-True ($toolNames -contains "list_templates") "list_templates tool is available"
    Assert-True ($toolNames -contains "create_demo_widget") "create_demo_widget tool is available"

    Write-Step "Testing tools/call:list_templates"
    $listTemplates = Invoke-JsonRpc -Method "tools/call" -Params @{
        name = "list_templates"
        arguments = @{}
    }
    $templatesJson = $listTemplates.result.content[0].text
    $templates = $templatesJson | ConvertFrom-Json
    Assert-True (($templates | Measure-Object).Count -gt 0) "list_templates returns at least one template"

    Write-Step "Testing tools/call:create_demo_widget"
    $templateId = $templates[0].id
    $demoResult = Invoke-JsonRpc -Method "tools/call" -Params @{
        name = "create_demo_widget"
        arguments = @{
            templateId = $templateId
            name = "Demo Day"
            ownerEmail = "demo@example.com"
        }
    }

    $textResponse = $demoResult.result.content[0].text
    $widgetHtml = $demoResult.result.content[1].text

    Assert-True ($textResponse -match "Demo Demo Day created") "create_demo_widget confirms demo creation"
    Assert-True ($widgetHtml -match "<!doctype html>") "create_demo_widget returns HTML document"
    Assert-True ($widgetHtml -match '<div id="root"></div>') "widget HTML includes root mount node"

    Write-Step "All local E2E checks passed. Ready for demo."
    Write-Host "Session ID used: $SessionId" -ForegroundColor Yellow
    Write-Host "Wrangler logs:" -ForegroundColor Yellow
    Write-Host "  stdout: $stdoutLog" -ForegroundColor Yellow
    Write-Host "  stderr: $stderrLog" -ForegroundColor Yellow

    if ($KeepRunning) {
        Write-Host "`nKeepRunning set: leaving pnpm dev running (PID $($devProcess.Id)). Press Ctrl+C when done." -ForegroundColor Yellow
        while (-not $devProcess.HasExited) {
            Start-Sleep -Seconds 1
        }
    }
}
finally {
    if ($null -ne $devProcess -and -not $KeepRunning -and -not $devProcess.HasExited) {
        Write-Step "Stopping pnpm dev (PID $($devProcess.Id))"
        Stop-Process -Id $devProcess.Id -Force
    }

    if ($env:OS -eq "Windows_NT" -and -not $KeepRunning) {
        $currentWranglerDev = @(
            Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine -match "wrangler dev" }
        )
        foreach ($proc in $currentWranglerDev) {
            if ($existingWranglerDevPids -notcontains $proc.ProcessId) {
                Write-Step "Stopping detached wrangler dev (PID $($proc.ProcessId))"
                Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if ($locationPushed) {
        Pop-Location
    }
}
