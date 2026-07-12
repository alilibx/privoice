// Retrieval eval harness (Task 11). Runs the FULL pipeline
// (retrieve -> fuse -> pinAndBoost -> packContext) offline and
// deterministically, against a fixed seeded corpus, and asserts:
//   1. recall@k             — the expected sourceId shows up in
//      result.sources for each fixture query
//   2. citation-correctness — every cited sourceId is one we actually seeded
//      (no fabricated sources)
//   3. attachment golden    — pinning surfaces the pinned doc first even on
//      a vague query that would not otherwise rank it first (the exact bug
//      v2 fixes)
//
// OFFLINE-BY-CONSTRUCTION:
// - rerank is bypassed via `cfg.rerankEnabled = false`, so `rerankCandidates`
//   (which calls OpenRouter) is never invoked and no `rerank` dep is needed.
// - the VECTOR arm is a deterministic keyword-overlap stand-in passed via
//   `deps.vector` (see `keywordOverlapVector` below) — no embeddings, no
//   network.
// - the BM25 arm is REAL: `deps.bm25` is left undefined, so `retrieve()`
//   falls back to the real `bm25Candidates`, which runs
//   `ctx.runQuery(internal.knowledge.searchQuery, ...)` against
//   `knowledgeChunks` rows seeded via the real `internal.knowledge
//   .insertChunks` mutation. This works because convex-test's `t.action`
//   accepts an inline function that receives a REAL ActionCtx (backed by
//   the local mock backend) — so `ctx.runQuery` behaves exactly as it
//   would in production, just against the in-memory test backend instead
//   of a real deployment, with zero network egress. So this eval exercises
//   real BM25 + real RRF fusion + real pin/boost + real context packing;
//   only the vector arm and the rerank stage are stubbed/skipped.

import { convexTest, type TestConvex } from "convex-test";
import { expect, test } from "vitest";
import schema from "../schema";
import { internal } from "../_generated/api";
import type { Id } from "../_generated/dataModel";
import type { ActionCtx } from "../_generated/server";
import { retrieve } from "./retrieve";
import { RETRIEVAL_CONFIG } from "./config";
import type { Candidate } from "./types";

// ---------------------------------------------------------------------------
// Fixed corpus: 2 documents + 2 meetings with known, distinctive content.
// ---------------------------------------------------------------------------
type CorpusEntry = {
  entryId: string;
  source: "document" | "meeting";
  sourceId: string;
  title: string;
  chunks: string[];
};

const CORPUS: CorpusEntry[] = [
  {
    entryId: "e-finance",
    source: "document",
    sourceId: "doc-finance",
    title: "Q3 Finance Report",
    chunks: [
      "Revenue grew 12% year over year in Q3, driven by strong enterprise sales.",
      "Gross profit margin improved to 58% thanks to lower cost of goods sold.",
    ],
  },
  {
    entryId: "e-onboarding",
    source: "document",
    sourceId: "doc-onboarding",
    title: "Employee Onboarding Guide",
    chunks: [
      "New hires should complete their laptop setup and badge request within the first week.",
      "Benefits enrollment must be completed within 30 days of the start date, and this is what determines eligibility for the annual bonus.",
    ],
  },
  {
    entryId: "e-standup",
    source: "meeting",
    sourceId: "meeting-standup",
    title: "Daily Standup",
    chunks: [
      "Action items from standup: Priya to fix the login bug, Sam to update the deploy script.",
      "Blockers: waiting on design review for the new dashboard widget.",
    ],
  },
  {
    entryId: "e-planning",
    source: "meeting",
    sourceId: "meeting-planning",
    title: "Sprint Planning",
    chunks: [
      "The team agreed to prioritize search performance work for next sprint.",
      "Capacity for the sprint is reduced due to two engineers being on vacation.",
    ],
  },
];

// A newly attached doc, seeded separately for the attachment-golden test.
// Its content deliberately overlaps a couple of words in the vague query
// ("is", "this") so it has SOME candidate presence in the vector arm even
// unpinned — but (see below) it scores lower than doc-onboarding's chunk on
// that same vague query, so unpinned it should NOT rank first. Pinning is
// what must put it at sources[0].
const DOC_NEW: CorpusEntry = {
  entryId: "e-new",
  source: "document",
  sourceId: "doc-new",
  title: "Untitled Attachment",
  chunks: ["This is a newly attached document that has not been reviewed yet."],
};

const ALL_SEEDED_IDS = new Set([...CORPUS, DOC_NEW].map((e) => e.sourceId));

// ---------------------------------------------------------------------------
// Deterministic offline "vector" arm: keyword-overlap scoring over the same
// seeded corpus. No embeddings, no network — just token-set intersection.
// Candidate `key` mirrors the bm25 arm's `${entryId}:${chunkIndex}` shape
// (see fuse.ts) so a chunk found by both arms dedupes onto one fusion key.
// ---------------------------------------------------------------------------
function tokenize(text: string): Set<string> {
  return new Set(text.toLowerCase().split(/\W+/).filter(Boolean));
}

function keywordOverlapVector(corpus: CorpusEntry[]) {
  return async (_ctx: ActionCtx, args: { query: string }): Promise<Candidate[]> => {
    const qTokens = tokenize(args.query);
    const out: Candidate[] = [];
    for (const entry of corpus) {
      entry.chunks.forEach((text, chunkIndex) => {
        const overlap = [...tokenize(text)].filter((t) => qTokens.has(t)).length;
        if (overlap > 0) {
          out.push({
            key: `${entry.entryId}:${chunkIndex}`,
            entryId: entry.entryId,
            source: entry.source,
            sourceId: entry.sourceId,
            title: entry.title,
            text,
            score: overlap,
          });
        }
      });
    }
    out.sort((a, b) => b.score - a.score);
    return out;
  };
}

const OFFLINE_CFG = { ...RETRIEVAL_CONFIG, rerankEnabled: false };

async function setup() {
  const t = convexTest(schema);
  const userId = await t.run((ctx) => ctx.db.insert("users", {} as any));
  for (const entry of [...CORPUS, DOC_NEW]) {
    await t.mutation(internal.knowledge.insertChunks, {
      userId,
      entryId: entry.entryId,
      source: entry.source,
      sourceId: entry.sourceId,
      title: entry.title,
      chunks: entry.chunks,
    });
  }
  return { t, userId };
}

// Runs `retrieve()` inside a REAL ActionCtx (t.action accepts an inline
// function per convex-test's API), so the default (real) bm25Candidates arm
// can call ctx.runQuery for real against the seeded knowledgeChunks table.
function runRetrieve(
  t: TestConvex<typeof schema>,
  userId: Id<"users">,
  opts: { query: string; pinnedSourceIds?: string[]; vectorCorpus?: CorpusEntry[] },
) {
  return t.action(async (ctx) =>
    retrieve(ctx, {
      userId,
      query: opts.query,
      pinnedSourceIds: opts.pinnedSourceIds ?? [],
      cfg: OFFLINE_CFG,
      deps: { vector: keywordOverlapVector(opts.vectorCorpus ?? CORPUS) },
    }),
  );
}

// ---------------------------------------------------------------------------
// 1. recall@k + 2. citation-correctness
// ---------------------------------------------------------------------------
const FIXTURES: Array<{ query: string; expect: string }> = [
  { query: "revenue growth", expect: "doc-finance" },
  { query: "action items from standup", expect: "meeting-standup" },
  { query: "benefits enrollment eligibility", expect: "doc-onboarding" },
  { query: "sprint planning capacity", expect: "meeting-planning" },
];

test("recall@k and citation-correctness across the fixed corpus", async () => {
  const { t, userId } = await setup();
  let hits = 0;

  for (const fixture of FIXTURES) {
    const result = await runRetrieve(t, userId, { query: fixture.query });
    const sourceIds = result.sources.map((s) => s.sourceId);

    // citation-correctness: never cite a source we didn't seed.
    for (const id of sourceIds) {
      expect(ALL_SEEDED_IDS.has(id), `fabricated sourceId cited: ${id}`).toBe(true);
    }

    if (sourceIds.includes(fixture.expect)) hits++;
    else {
      // Surface the miss with context for easier debugging if this ever
      // regresses.
      console.error(
        `recall miss: query=${JSON.stringify(fixture.query)} expected=${fixture.expect} got=${JSON.stringify(sourceIds)}`,
      );
    }
    expect(sourceIds, `expected "${fixture.expect}" for query "${fixture.query}"`).toContain(
      fixture.expect,
    );
  }

  const recall = hits / FIXTURES.length;
  console.log(`retrieval eval: recall@k = ${(recall * 100).toFixed(0)}% (${hits}/${FIXTURES.length})`);
  expect(recall).toBe(1);
});

// ---------------------------------------------------------------------------
// 3. attachment golden — pinning beats natural rank on a vague query.
// ---------------------------------------------------------------------------
test("attachment golden: pinned doc-new is sources[0] on a vague query", async () => {
  const { t, userId } = await setup();
  const fullCorpus = [...CORPUS, DOC_NEW];

  // Sanity check: WITHOUT pinning, the vague query should not naturally
  // surface doc-new first (doc-onboarding's chunk overlaps the vague query
  // on more tokens — see DOC_NEW's comment above). This proves the
  // assertion below is actually exercising the pin mechanism, not a
  // coincidence of natural ranking.
  const unpinned = await runRetrieve(t, userId, {
    query: "what is this",
    vectorCorpus: fullCorpus,
  });
  expect(unpinned.sources[0]?.sourceId).not.toBe("doc-new");

  const pinned = await runRetrieve(t, userId, {
    query: "what is this",
    pinnedSourceIds: ["doc-new"],
    vectorCorpus: fullCorpus,
  });
  expect(pinned.sources[0]?.sourceId).toBe("doc-new");

  // citation-correctness holds for this query too.
  for (const s of pinned.sources) {
    expect(ALL_SEEDED_IDS.has(s.sourceId)).toBe(true);
  }
});
