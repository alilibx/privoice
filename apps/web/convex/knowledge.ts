import { v } from "convex/values";
import { internalMutation, internalQuery, type QueryCtx } from "./_generated/server";
import type { Id } from "./_generated/dataModel";

export const insertChunks = internalMutation({
  args: {
    userId: v.id("users"),
    entryId: v.string(),
    source: v.string(),
    sourceId: v.string(),
    title: v.string(),
    chunks: v.array(v.string()),
  },
  handler: async (ctx, { userId, entryId, source, sourceId, title, chunks }) => {
    for (let i = 0; i < chunks.length; i++) {
      await ctx.db.insert("knowledgeChunks", {
        userId, entryId, source, sourceId, title,
        chunkText: chunks[i], chunkIndex: i,
      });
    }
  },
});

export const deleteBySource = internalMutation({
  args: { userId: v.id("users"), source: v.string(), sourceId: v.string() },
  handler: async (ctx, { userId, source, sourceId }) => {
    const rows = await ctx.db
      .query("knowledgeChunks")
      .withIndex("by_source", (q) =>
        q.eq("userId", userId).eq("source", source).eq("sourceId", sourceId),
      )
      .collect();
    for (const row of rows) await ctx.db.delete(row._id);
  },
});

export type Bm25Hit = {
  entryId: string; source: string; sourceId: string;
  title: string; chunkText: string; chunkIndex: number;
};

export async function bm25Search(
  ctx: QueryCtx,
  args: { userId: Id<"users">; query: string; source?: string; limit: number },
): Promise<Bm25Hit[]> {
  const q = args.query.trim();
  if (q.length === 0) return [];
  const rows = await ctx.db
    .query("knowledgeChunks")
    .withSearchIndex("by_text", (s) => {
      let b = s.search("chunkText", q).eq("userId", args.userId);
      if (args.source) b = b.eq("source", args.source);
      return b;
    })
    .take(args.limit);
  return rows.map((r) => ({
    entryId: r.entryId, source: r.source, sourceId: r.sourceId,
    title: r.title, chunkText: r.chunkText, chunkIndex: r.chunkIndex,
  }));
}

/**
 * Internal query wrapper around `bm25Search`, for callers (like
 * `retrieval/candidates.ts`'s `bm25Candidates`) that run inside an
 * ActionCtx and so cannot touch `ctx.db` directly — `ctx.runQuery` bridges
 * into a QueryCtx that `bm25Search` can use.
 */
export const searchQuery = internalQuery({
  args: {
    userId: v.id("users"),
    query: v.string(),
    source: v.optional(v.string()),
    limit: v.number(),
  },
  handler: async (ctx, args): Promise<Bm25Hit[]> => bm25Search(ctx, args),
});
