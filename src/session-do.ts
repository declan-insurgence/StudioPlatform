export type SessionState = {
  sessionId: string;
  requestCount: number;
  demos: Array<{ id: string; name: string; templateId: string }>;
};

export class SessionDO extends DurableObject {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/state") {
      const state = (await this.ctx.storage.get<SessionState>("state")) ?? {
        sessionId: this.ctx.id.toString(),
        requestCount: 0,
        demos: [],
      };
      return Response.json(state);
    }

    if (request.method === "POST" && url.pathname === "/state") {
      const patch = (await request.json()) as Partial<SessionState>;
      const current = (await this.ctx.storage.get<SessionState>("state")) ?? {
        sessionId: this.ctx.id.toString(),
        requestCount: 0,
        demos: [],
      };
      const merged: SessionState = { ...current, ...patch };
      await this.ctx.storage.put("state", merged);
      return Response.json(merged);
    }

    return new Response("Not found", { status: 404 });
  }
}
