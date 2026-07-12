import { expect, test } from "vitest";
import { pinAndBoost, packContext } from "./pack";
import { RETRIEVAL_CONFIG } from "./config";
import type { Candidate } from "./types";
const c = (sourceId: string): Candidate => ({
  key: sourceId, entryId: sourceId, source: "document", sourceId,
  title: `T-${sourceId}`, text: `body ${sourceId}`, score: 1,
});

test("pinned sources move to the front, none dropped", () => {
  const out = pinAndBoost([c("a"), c("b"), c("c")], ["c"]);
  expect(out.map((x) => x.sourceId)).toEqual(["c", "a", "b"]);
  expect(out).toHaveLength(3);
});

test("pack numbers sources and returns matching SourceRefs", () => {
  const { pack, sources } = packContext([c("a"), c("b")], RETRIEVAL_CONFIG);
  expect(pack).toContain("[1]");
  expect(pack).toContain("[2]");
  expect(pack).toContain("T-a");
  expect(sources).toHaveLength(2);
  expect(sources[0]).toMatchObject({ n: 1, sourceId: "a", title: "T-a" });
});
