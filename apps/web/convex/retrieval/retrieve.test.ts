import { expect, test } from "vitest";
import { retrieve } from "./retrieve";
import { RETRIEVAL_CONFIG } from "./config";
import type { Candidate } from "./types";
const c = (k: string): Candidate => ({ key: k, entryId: k, source: "document", sourceId: k, title: k, text: k, score: 1 });

test("pipeline returns a pack + sources, pinned first", async () => {
  const res = await retrieve({} as any, {
    userId: "u1", query: "revenue", pinnedSourceIds: ["b"],
    deps: {
      vector: async () => [c("a"), c("b")],
      bm25: async () => [c("b"), c("c")],
      rerank: async (cands) => cands.slice(0, 8),
    },
  });
  expect(res.sources[0].sourceId).toBe("b"); // pinned to front
  expect(res.pack).toContain("[1]");
});

test("no candidates yields an explicit empty result", async () => {
  const res = await retrieve({} as any, {
    userId: "u1", query: "x", pinnedSourceIds: [],
    deps: { vector: async () => [], bm25: async () => [], rerank: async (c) => c },
  });
  expect(res.sources).toHaveLength(0);
  expect(res.pack).toMatch(/no matching/i);
});

// B2 regression: a pinned source must survive rerank even if the reranker
// (adversarially, or just because it disagreed) drops it from its chosen
// keepN. Simulate the worst case: `deps.rerank` returns ONLY non-pinned
// candidates, never including "b" at all.
test("pinned source survives an adversarial rerank that drops it", async () => {
  const res = await retrieve({} as any, {
    userId: "u1", query: "revenue", pinnedSourceIds: ["b"],
    cfg: { ...RETRIEVAL_CONFIG, rerankEnabled: true },
    deps: {
      vector: async () => [c("a"), c("b")],
      bm25: async () => [c("b"), c("c")],
      // Adversarial: never returns "b", even though it was in the pool.
      rerank: async () => [c("a"), c("c")],
    },
  });
  const sourceIds = res.sources.map((s) => s.sourceId);
  expect(sourceIds).toContain("b");
  expect(res.sources[0]?.sourceId).toBe("b");
});
