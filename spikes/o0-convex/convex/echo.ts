import { mutation } from "./_generated/server";
import { v } from "convex/values";

// Round-trips a payload through a mutation: proves writes/args/return values
// marshal correctly between Flutter and Convex.
export const echo = mutation({
  args: { message: v.string() },
  handler: async (_ctx, { message }) => {
    return { echoed: message, len: message.length, ts: Date.now() };
  },
});
