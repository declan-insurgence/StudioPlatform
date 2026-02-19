import { createDemoFromTemplate, listApprovedTemplates } from "./data";
import { SessionDO, type SessionState } from "./session-do";

export { SessionDO };

type Env = {
  SESSION_DO: DurableObjectNamespace<SessionDO>;
  ASSETS: Fetcher;
};

type JsonRpcRequest = {
  id?: string | number | null;
  jsonrpc?: string;
  method: string;
  params?: Record<string, unknown>;
};

const sseClients = new Map<string, WritableStreamDefaultWriter<string>>();

function jsonRpcResult(id: JsonRpcRequest["id"], result: unknown) {
  return { jsonrpc: "2.0", id: id ?? null, result };
}

async function getSessionStub(env: Env, sessionId: string) {
  const id = env.SESSION_DO.idFromName(sessionId);
  return env.SESSION_DO.get(id);
}

async function getSessionState(env: Env, sessionId: string): Promise<SessionState> {
  const stub = await getSessionStub(env, sessionId);
  const response = await stub.fetch("https://session/state");
  return (await response.json()) as SessionState;
}

async function setSessionState(env: Env, sessionId: string, patch: Partial<SessionState>): Promise<SessionState> {
  const stub = await getSessionStub(env, sessionId);
  const response = await stub.fetch("https://session/state", {
    method: "POST",
    body: JSON.stringify(patch),
  });
  return (await response.json()) as SessionState;
}

async function loadWidgetHtml(env: Env): Promise<string> {
  const [jsResponse, cssResponse] = await Promise.all([
    env.ASSETS.fetch("https://assets.local/index.js"),
    env.ASSETS.fetch("https://assets.local/style.css"),
  ]);

  const js = jsResponse.ok ? await jsResponse.text() : "console.error('widget js missing');";
  const css = cssResponse.ok ? await cssResponse.text() : "";

  return `<!doctype html><html><head><meta charset=\"utf-8\"/><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"/><style>${css}</style></head><body><div id=\"root\"></div><script>${js}</script></body></html>`;
}

async function handleMcp(req: JsonRpcRequest, env: Env, sessionId: string) {
  const session = await getSessionState(env, sessionId);
  await setSessionState(env, sessionId, { requestCount: session.requestCount + 1 });

  if (req.method === "initialize") {
    return jsonRpcResult(req.id, {
      protocolVersion: "2024-11-05",
      serverInfo: { name: "studio-platform-mcp", version: "0.1.0" },
      capabilities: { tools: {} },
    });
  }

  if (req.method === "tools/list") {
    return jsonRpcResult(req.id, {
      tools: [
        {
          name: "list_templates",
          description: "List approved demo templates.",
          inputSchema: { type: "object", properties: {}, additionalProperties: false },
        },
        {
          name: "create_demo_widget",
          description: "Create a demo and return self-contained widget HTML.",
          inputSchema: {
            type: "object",
            properties: {
              templateId: { type: "string" },
              name: { type: "string" },
              ownerEmail: { type: "string" },
            },
            required: ["templateId", "name", "ownerEmail"],
          },
        },
      ],
    });
  }

  if (req.method === "tools/call") {
    const params = req.params ?? {};
    const toolName = String(params.name ?? "");

    if (toolName === "list_templates") {
      return jsonRpcResult(req.id, {
        content: [{ type: "text", text: JSON.stringify(listApprovedTemplates(), null, 2) }],
      });
    }

    if (toolName === "create_demo_widget") {
      const args = (params.arguments ?? {}) as Record<string, string>;
      const demo = createDemoFromTemplate(args.templateId, args.name, args.ownerEmail);
      const updated = await setSessionState(env, sessionId, {
        demos: [...session.demos, { id: demo.id, name: demo.name, templateId: demo.templateId }],
      });
      const widgetHtml = await loadWidgetHtml(env);
      return jsonRpcResult(req.id, {
        content: [
          { type: "text", text: `Demo ${demo.name} created. Session demos: ${updated.demos.length}.` },
          { type: "text", text: widgetHtml },
        ],
      });
    }
  }

  return {
    jsonrpc: "2.0",
    id: req.id ?? null,
    error: { code: -32601, message: `Method not found: ${req.method}` },
  };
}

async function handleSse(sessionId: string) {
  const stream = new TransformStream<string, Uint8Array>({
    transform(chunk, controller) {
      controller.enqueue(new TextEncoder().encode(chunk));
    },
  });

  const writer = stream.writable.getWriter();
  sseClients.set(sessionId, writer);
  await writer.write(`event: ready\ndata: ${JSON.stringify({ sessionId })}\n\n`);

  return new Response(stream.readable, {
    headers: {
      "content-type": "text/event-stream",
      "cache-control": "no-cache",
      connection: "keep-alive",
      "x-session-id": sessionId,
    },
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return new Response("ok", { status: 200 });
    }

    if (url.pathname === "/") {
      return Response.json({
        name: "Studio Platform MCP Worker",
        connect: {
          sse: `${url.origin}/sse`,
          streamableHttp: `${url.origin}/mcp`,
        },
      });
    }

    if (url.pathname === "/sse" && request.method === "GET") {
      const sessionId = request.headers.get("x-session-id") ?? crypto.randomUUID();
      return handleSse(sessionId);
    }

    if (url.pathname === "/mcp" && request.method === "POST") {
      const sessionId = request.headers.get("x-session-id") ?? crypto.randomUUID();
      const payload = (await request.json()) as JsonRpcRequest;
      const responsePayload = await handleMcp(payload, env, sessionId);
      const writer = sseClients.get(sessionId);
      if (writer) {
        await writer.write(`event: message\ndata: ${JSON.stringify(responsePayload)}\n\n`);
      }
      return Response.json(responsePayload, { headers: { "x-session-id": sessionId } });
    }

    return new Response("Not found", { status: 404 });
  },
};
