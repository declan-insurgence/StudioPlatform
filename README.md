# Studio Platform MCP on Cloudflare Workers

This repository now runs as a **single Cloudflare Worker deployment** that hosts:
- A remote MCP server (`/sse` + `/mcp`)
- Stateful MCP sessions via Durable Objects
- A self-contained React widget (JS/CSS inlined into HTML tool output)

## Architecture

```text
src/
  index.ts        # Worker entry + MCP server routes
  data.ts         # Domain logic used by MCP tools
  session-do.ts   # Durable Object for session state
widget/
  src/index.tsx   # Widget entry point
  src/app.tsx     # Widget UI
  vite.config.ts  # Build emits index.js + style.css for inlining
.github/workflows/deploy.yml
wrangler.toml
```

## Local development

```bash
pnpm install
pnpm --dir widget install
pnpm dev
```

Worker runs on `http://localhost:8787`.

### Useful scripts

- `pnpm build` - build widget and dry-run worker bundle
- `pnpm tunnel` - expose localhost for ChatGPT testing
- `pnpm inspector` - run MCP inspector against `http://localhost:8787/sse`
- `pnpm deploy:dev|test|prod`
- `pnpm logs:dev|test|prod`

## Connecting to ChatGPT

1. Deploy (or tunnel) the worker.
2. In ChatGPT MCP connector setup, use the Worker **SSE URL**:
   - `https://<your-worker-domain>/sse`
3. The streamable HTTP endpoint is:
   - `https://<your-worker-domain>/mcp`
4. Verify health:
   - `https://<your-worker-domain>/health` should return `ok`

### Local endpoint checklist

- `GET http://localhost:8787/` => connection instructions JSON
- `GET http://localhost:8787/health` => 200 OK
- `GET http://localhost:8787/sse` => SSE transport
- `POST http://localhost:8787/mcp` => streamable HTTP MCP

### Troubleshooting

- If widget HTML is blank, run `pnpm --dir widget build` and redeploy.
- If ChatGPT connection fails, ensure you configured the `/sse` URL (not root).
- If state is not retained, verify Durable Object binding `SESSION_DO` is present in `wrangler.toml` and deployed migration `v1` was applied.

## CI/CD

GitHub Actions workflow `.github/workflows/deploy.yml` deploys:
- **dev** on pull request opened/updated
- **test** on pushes to `main`
- **prod** via `workflow_dispatch`

Use GitHub environments `dev`, `test`, `prod` and add protection rules to `prod` for manual approval.
