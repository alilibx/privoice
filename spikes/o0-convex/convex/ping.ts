import { query } from "./_generated/server";

// Simplest possible read: proves the Convex client (WebSocket sync) can call a
// query from Flutter via convex_flutter and get a typed result back.
export const ping = query({
  args: {},
  handler: async () => {
    return { ok: true, service: "privoice-o0-spike", ts: Date.now() };
  },
});
