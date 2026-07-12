import { rag } from "../rag";
import { internal } from "../_generated/api";
import type { ActionCtx } from "../_generated/server";
import type { Id } from "../_generated/dataModel";
import type { Candidate, RetrievalConfig } from "./types";

type CandidateArgs = {
  userId: string;
  query: string;
  source?: string;
  cfg: RetrievalConfig;
};

/**
 * Vector-search arm. Runs `rag.search` (namespace = userId, optionally
 * filtered to one `source`) and maps each `SearchResult` to a `Candidate`.
 * Per fuse.ts's fusion-key decision, the key is chunk-level:
 * `${entryId}:${order}`, where `order` is the verified stable per-chunk
 * index on `SearchResult` (see `node_modules/@convex-dev/rag/dist/shared.d.ts`).
 * `title`/`source`/`sourceId` come from the matching `entries[]` entry's
 * metadata (set by `ragAdd` in `../rag.ts`), keyed by `entryId`, since
 * `SearchResult` itself only carries `entryId`/`order`/`content`/`score`.
 */
export async function vectorCandidates(
  ctx: ActionCtx,
  { userId, query, source, cfg }: CandidateArgs,
): Promise<Candidate[]> {
  const { results, entries } = await rag.search(ctx, {
    namespace: userId,
    query,
    limit: cfg.candidateK,
    chunkContext: cfg.chunkContext,
    vectorScoreThreshold: cfg.vectorScoreThreshold,
    filters: source ? [{ name: "source", value: source }] : undefined,
  });
  const entryById = new Map(entries.map((e) => [String(e.entryId), e]));
  return results.map((r): Candidate => {
    const entryId = String(r.entryId);
    const entry = entryById.get(entryId);
    const meta = (entry?.metadata ?? {}) as {
      title?: string;
      source?: string;
      sourceId?: string;
    };
    return {
      key: `${entryId}:${r.order}`,
      entryId,
      source: meta.source ?? source ?? "",
      sourceId: meta.sourceId ?? entry?.key ?? "",
      title: entry?.title ?? meta.title ?? "",
      text: r.content.map((c) => c.text).join("\n\n"),
      score: r.score,
    };
  });
}

/**
 * BM25 arm. `bm25Search` needs a QueryCtx (`ctx.db`), which an ActionCtx
 * lacks, so this routes through `internal.knowledge.searchQuery` (an
 * internalQuery wrapper) via `ctx.runQuery`. Per fuse.ts's fusion-key
 * decision, the key mirrors the vector arm's: `${entryId}:${chunkIndex}`,
 * using `Bm25Hit.chunkIndex` as the stable per-chunk identity.
 */
export async function bm25Candidates(
  ctx: ActionCtx,
  { userId, query, source, cfg }: CandidateArgs,
): Promise<Candidate[]> {
  const hits = await ctx.runQuery(internal.knowledge.searchQuery, {
    userId: userId as Id<"users">,
    query,
    source,
    limit: cfg.candidateK,
  });
  return hits.map(
    (h, i): Candidate => ({
      key: `${h.entryId}:${h.chunkIndex}`,
      entryId: h.entryId,
      source: h.source,
      sourceId: h.sourceId,
      title: h.title,
      text: h.chunkText,
      // bm25Search doesn't return a raw BM25 score, so use a rank-derived
      // proxy (higher = better) consistent with `Candidate.score`'s
      // "arm-native score" contract; hybridRank only needs key ORDER
      // (this array is already sorted best-first), not this score value.
      score: hits.length - i,
    }),
  );
}
