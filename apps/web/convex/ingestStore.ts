import { v } from "convex/values";
import { internalQuery, internalMutation } from "./_generated/server";

export const getDoc = internalQuery({
  args: { documentId: v.id("documents") },
  handler: (ctx, { documentId }) => ctx.db.get(documentId),
});

export const setReady = internalMutation({
  args: { documentId: v.id("documents"), chunkCount: v.number() },
  handler: (ctx, { documentId, chunkCount }) =>
    ctx.db.patch(documentId, { status: "ready", chunkCount }),
});

export const setFailed = internalMutation({
  args: { documentId: v.id("documents"), error: v.string() },
  handler: (ctx, { documentId, error }) =>
    ctx.db.patch(documentId, { status: "failed", error }),
});
