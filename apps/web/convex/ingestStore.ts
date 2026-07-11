import { v } from "convex/values";
import { internalQuery, internalMutation } from "./_generated/server";

export const getDoc = internalQuery({
  args: { documentId: v.id("documents") },
  handler: (ctx, { documentId }) => ctx.db.get(documentId),
});

export const insertChunks = internalMutation({
  args: {
    documentId: v.id("documents"),
    userId: v.id("users"),
    chunks: v.array(v.object({ text: v.string(), embedding: v.array(v.float64()) })),
  },
  handler: async (ctx, { documentId, userId, chunks }) => {
    for (let i = 0; i < chunks.length; i++) {
      await ctx.db.insert("documentChunks", {
        userId, documentId, chunkIndex: i,
        text: chunks[i].text, embedding: chunks[i].embedding,
      });
    }
  },
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
