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

/**
 * Concatenated chunk text for one user-owned source, in chunk order — used
 * by tools.ts's `readDocument` (positional read) and scoped `grep` to work
 * within a single known source (e.g. one document or meeting).
 * Scoped via `by_user_sourceId` on (userId, sourceId), so a caller can never
 * read another user's chunks even if it somehow guessed a valid sourceId.
 * Returns "" if the user has no chunks for that sourceId.
 */
export const linesFor = internalQuery({
  args: { userId: v.id("users"), sourceId: v.string() },
  handler: async (ctx, { userId, sourceId }): Promise<string> => {
    const rows = await ctx.db
      .query("knowledgeChunks")
      .withIndex("by_user_sourceId", (q) =>
        q.eq("userId", userId).eq("sourceId", sourceId),
      )
      .collect();
    rows.sort((a, b) => a.chunkIndex - b.chunkIndex);
    return rows.map((r) => r.chunkText).join("\n");
  },
});

// Group all of a user's knowledgeChunks by sourceId and reconstruct each
// source's full text (chunks sorted by chunkIndex, joined with "\n") — the
// same reconstruction linesFor does for one source, done for the whole
// corpus in a single by_user scan. Backs corpus-mode grep and line counts.
export async function reconstructedSourcesForUser(
  ctx: QueryCtx,
  userId: Id<"users">,
): Promise<Array<{ sourceId: string; title: string; source: string; text: string }>> {
  const rows = await ctx.db
    .query("knowledgeChunks")
    .withIndex("by_user", (q) => q.eq("userId", userId))
    .collect();
  const groups = new Map<
    string,
    { title: string; source: string; chunks: Array<{ i: number; t: string }> }
  >();
  for (const r of rows) {
    let g = groups.get(r.sourceId);
    if (!g) {
      g = { title: r.title, source: r.source, chunks: [] };
      groups.set(r.sourceId, g);
    }
    g.chunks.push({ i: r.chunkIndex, t: r.chunkText });
  }
  return [...groups.entries()].map(([sourceId, g]) => ({
    sourceId,
    title: g.title,
    source: g.source,
    text: g.chunks.sort((a, b) => a.i - b.i).map((c) => c.t).join("\n"),
  }));
}

export const corpusForUser = internalQuery({
  args: { userId: v.id("users") },
  handler: (ctx, { userId }) => reconstructedSourcesForUser(ctx, userId),
});

export async function lineCountsForUser(
  ctx: QueryCtx,
  userId: Id<"users">,
): Promise<Record<string, number>> {
  const sources = await reconstructedSourcesForUser(ctx, userId);
  const counts: Record<string, number> = {};
  for (const s of sources) {
    counts[s.sourceId] = s.text.length === 0 ? 0 : s.text.split("\n").length;
  }
  return counts;
}
