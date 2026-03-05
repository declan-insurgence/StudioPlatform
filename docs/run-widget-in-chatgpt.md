# Run The Widget Locally And Use It In ChatGPT

This guide shows how to:
- run the worker + widget locally,
- generate the demo widget HTML,
- connect the MCP server to ChatGPT.

## Prerequisites

- Node.js 20+
- `pnpm`
- PowerShell (Windows)
- A ChatGPT plan that supports custom connectors/MCP
- For public access: Cloudflare account + Wrangler auth, or `cloudflared` for tunneling

## 1) Install Dependencies

From repo root:

```powershell
pnpm install
pnpm --dir widget install
```

## 2) Run Local E2E Demo Harness

This builds the widget, starts `wrangler dev`, and verifies `/`, `/health`, `/sse`, and `/mcp`.

```powershell
.\scripts\local-e2e-demo.ps1 -KeepRunning
```

Keep this terminal open.

## 3) Generate And Open The Widget UI

Open a second terminal in the same repo and run:

```powershell
$baseUrl="http://127.0.0.1:8787"; $session="demo-session"

$list = @{jsonrpc="2.0";id="1";method="tools/call";params=@{name="list_templates";arguments=@{}}} | ConvertTo-Json -Depth 10
$listResp = Invoke-RestMethod -Uri "$baseUrl/mcp" -Method Post -Headers @{"x-session-id"=$session} -ContentType "application/json" -Body $list
$templateId = (($listResp.result.content[0].text | ConvertFrom-Json)[0].id)

$create = @{jsonrpc="2.0";id="2";method="tools/call";params=@{name="create_demo_widget";arguments=@{templateId=$templateId;name="Demo Day";ownerEmail="demo@example.com"}}} | ConvertTo-Json -Depth 10
$resp = Invoke-RestMethod -Uri "$baseUrl/mcp" -Method Post -Headers @{"x-session-id"=$session} -ContentType "application/json" -Body $create
$resp.result.content[1].text | Set-Content .\demo-widget.html -Encoding UTF8
Start-Process .\demo-widget.html
```

You should see the widget page with the `Demo Studio Widget` title.

## 4) Expose The MCP Server Publicly (Required For ChatGPT)

ChatGPT cannot connect to `localhost`. You need a public URL.

### Option A: Deploy to Cloudflare

```powershell
pnpm deploy:dev
```

Use:
- `https://<your-worker-domain>/sse` (for connector setup)
- `https://<your-worker-domain>/mcp` (streamable HTTP endpoint)

### Option B: Tunnel Localhost

If `cloudflared` is installed:

```powershell
pnpm dev
pnpm tunnel
```

Use the tunnel URL + `/sse` in ChatGPT.

## 5) Connect In ChatGPT

In ChatGPT, add a custom MCP connector/app using your public SSE endpoint:

- `https://<public-domain>/sse`

Then start a chat with that connector enabled and ask for tool usage, for example:

- "List templates."
- "Create a demo widget for template `<id>` with name `Demo Day` and owner `demo@example.com`."

## 6) Verify Endpoints Quickly

Health check:

```text
GET https://<public-domain>/health
```

Expected response body:

```text
ok
```

## Troubleshooting

- If `pwsh` is not found on Windows, run the script directly in PowerShell:
  - `.\scripts\local-e2e-demo.ps1 -KeepRunning`
- If the widget appears blank, rebuild widget assets and regenerate `demo-widget.html`:
  - `pnpm --dir widget build`
- If ChatGPT cannot connect, confirm you used `/sse` (not root URL).
