import { expect, test } from "vitest";
import { rerankCandidates } from "./rerank";
import { RETRIEVAL_CONFIG } from "./config";
import type { Candidate } from "./types";
const cfg = { ...RETRIEVAL_CONFIG, keepN: 2, rerankPool: 5 };
const cand = (k: string): Candidate => ({ key: k, entryId: k, source: "document", sourceId: k, title: k, text: k, score: 1 });

test("keeps and orders by the model's chosen indices", async () => {
  const fused = [cand("a"), cand("b"), cand("c")];
  const out = await rerankCandidates(fused, "q", cfg, {
    generate: async () => JSON.stringify({ keep: [2, 0] }),
  });
  expect(out.map((x) => x.key)).toEqual(["c", "a"]);
});

test("fails soft to fused top-N on bad output", async () => {
  const fused = [cand("a"), cand("b"), cand("c")];
  const out = await rerankCandidates(fused, "q", cfg, {
    generate: async () => "not json",
  });
  expect(out.map((x) => x.key)).toEqual(["a", "b"]);
});

test("fails soft on thrown error", async () => {
  const fused = [cand("a"), cand("b"), cand("c")];
  const out = await rerankCandidates(fused, "q", cfg, {
    generate: async () => {
      throw new Error("timeout");
    },
  });
  expect(out.map((x) => x.key)).toEqual(["a", "b"]);
});
