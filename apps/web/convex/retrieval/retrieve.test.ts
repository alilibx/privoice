import { expect, test } from "vitest";
import { retrieve } from "./retrieve";
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
