import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";

// Plain-HTTP surface (no Convex client library needed). This is the path the
// headless Dart smoke test hits, and the fallback transport if convex_flutter
// turns out to be unviable on a target platform.
const http = httpRouter();

http.route({
  path: "/ping",
  method: "GET",
  handler: httpAction(async () => {
    return new Response(
      JSON.stringify({ ok: true, via: "httpAction", ts: Date.now() }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  }),
});

http.route({
  path: "/echo",
  method: "POST",
  handler: httpAction(async (_ctx, request) => {
    const body = await request.json().catch(() => ({}));
    const message = typeof body?.message === "string" ? body.message : "";
    return new Response(
      JSON.stringify({ echoed: message, len: message.length, via: "httpAction" }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  }),
});

export default http;
