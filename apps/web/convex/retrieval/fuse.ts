// FUSION-KEY GATE (Task 3, Step 1):
//
// Inspected `node_modules/@convex-dev/rag/dist/shared.d.ts`'s `vSearchResult`
// (aka `SearchResult`): each result item is
//   { entryId: EntryId; order: number; content: {text, metadata}[];
//     startOrder: number; score: number }
// `order` is a stable per-chunk index within the entry (the chunk's position
// before `chunkContext` expansion widens `content`/`startOrder` around it).
// That's a stable per-chunk identity alongside `entryId`, so per the brief's
// decision rule we use the CHUNK-LEVEL key:
//   vector candidates: `${entryId}:${order}`
// `knowledge.ts`'s `Bm25Hit` carries the matching per-chunk identity as
// `chunkIndex`, so BM25 candidates use the same shape:
//   bm25 candidates:   `${entryId}:${chunkIndex}`
// This lets a chunk that both arms retrieve independently dedupe onto the
// same fusion key, while still letting adjacent chunks of the same entry
// rank (and appear) separately when only one arm finds them.

import { hybridRank } from "@convex-dev/rag";
import type { Candidate, RetrievalConfig } from "./types";

export function fuseCandidates(
  bm25: Candidate[],
  vector: Candidate[],
  cfg: RetrievalConfig,
): Candidate[] {
  const byKey = new Map<string, Candidate>();
  for (const cand of [...vector, ...bm25]) {
    if (!byKey.has(cand.key)) byKey.set(cand.key, cand);
  }
  const order = hybridRank([bm25.map((c) => c.key), vector.map((c) => c.key)], {
    weights: cfg.fuseWeights,
    k: cfg.rrfK,
  });
  return order.map((k) => byKey.get(k)!).filter(Boolean);
}
