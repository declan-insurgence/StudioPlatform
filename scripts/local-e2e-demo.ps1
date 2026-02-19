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

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$logDir = Join-Path $repoRoot ".tmp"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$stdoutLog = Join-Path $logDir "wrangler-dev.stdout.log"
$stderrLog = Join-Path $logDir "wrangler-dev.stderr.log"

$devProcess = $null

try {
    Write-Step "Validating prerequisites"
    $required = @("node", "pnpm")
    foreach ($cmd in $required) {
        $exists = Get-Command $cmd -ErrorAction SilentlyContinue
        Assert-True ($null -ne $exists) "$cmd is available"
    }

    Push-Location $repoRoot

    if (-not $SkipInstall) {
        Write-Step "Installing dependencies"
        & pnpm install --frozen-lockfile
        & pnpm --dir widget install --frozen-lockfile
    }

    Write-Step "Building widget assets"
    & pnpm --dir widget build

    Write-Step "Starting worker locally (pnpm dev)"
    if (Test-Path $stdoutLog) { Remove-Item $stdoutLog -Force }
    if (Test-Path $stderrLog) { Remove-Item $stderrLog -Force }

    $devProcess = Start-Process -FilePath "pnpm" -ArgumentList "dev" -WorkingDirectory $repoRoot -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -PassThru
    Assert-True (-not $devProcess.HasExited) "wrangler dev process started"

    Write-Step "Waiting for /health to become ready"
    $deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 750
        try {
            $health = Invoke-WebRequest -Uri "$BaseUrl/health" -Method Get -TimeoutSec 2
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
    $httpClient = [System.Net.Http.HttpClient]::new()
    $request = $null
    $response = $null
    try {
        $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, "$BaseUrl/sse")
        $request.Headers.Add("x-session-id", $SessionId)
        $response = $httpClient.Send($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead)
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
    Assert-True ($widgetHtml -match "<div id=\"root\"></div>") "widget HTML includes root mount node"

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

    Pop-Location
}
