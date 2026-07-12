import { expect, test } from "vitest";
import { fuseCandidates } from "./fuse";
import { RETRIEVAL_CONFIG } from "./config";
import type { Candidate } from "./types";

const c = (key: string, score = 1): Candidate => ({
  key,
  entryId: key,
  source: "document",
  sourceId: key,
  title: key,
  text: key,
  score,
});

test("fusion favors items ranked highly in both arms", () => {
  const bm25 = [c("a"), c("b"), c("c")];
  const vector = [c("b"), c("c"), c("a")];
  const fused = fuseCandidates(bm25, vector, RETRIEVAL_CONFIG);
  expect(fused.map((x) => x.key)).toEqual(["b", "a", "c"]);
});

test("dedupes items present in both arms", () => {
  const fused = fuseCandidates([c("a"), c("b")], [c("a")], RETRIEVAL_CONFIG);
  expect(fused.filter((x) => x.key === "a")).toHaveLength(1);
});
