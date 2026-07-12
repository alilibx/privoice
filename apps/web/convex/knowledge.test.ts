import { convexTest } from "convex-test";
import { expect, test } from "vitest";
import schema from "./schema";
import { internal } from "./_generated/api";
import {
  bm25Search,
  reconstructedSourcesForUser,
  lineCountsForUser,
} from "./knowledge";

test("insert then bm25 search returns matching chunks, delete removes them", async () => {
  const t = convexTest(schema);
  const userId = await t.run(async (ctx) =>
    ctx.db.insert("users", {} as any),
  );
  await t.mutation(internal.knowledge.insertChunks, {
    userId,
    entryId: "e1",
    source: "document",
    sourceId: "d1",
    title: "Q3 report",
    chunks: ["Revenue grew twelve percent this quarter", "Costs held flat"],
  });

  const hits = await t.run((ctx) =>
    bm25Search(ctx, { userId, query: "revenue", limit: 10 }),
  );
  expect(hits.length).toBeGreaterThan(0);
  expect(hits[0].sourceId).toBe("d1");
  expect(hits[0].chunkText).toMatch(/revenue/i);

  await t.mutation(internal.knowledge.deleteBySource, {
    userId,
    source: "document",
    sourceId: "d1",
  });
  const after = await t.run((ctx) =>
    bm25Search(ctx, { userId, query: "revenue", limit: 10 }),
  );
  expect(after).toHaveLength(0);
});

test("linesFor returns a user's chunk text in order, scoped by sourceId, and empty for a stranger", async () => {
  const t = convexTest(schema);
  const userId = await t.run(async (ctx) => ctx.db.insert("users", {} as any));
  const otherUserId = await t.run(async (ctx) =>
    ctx.db.insert("users", {} as any),
  );
  await t.mutation(internal.knowledge.insertChunks, {
    userId,
    entryId: "e1",
    source: "document",
    sourceId: "d1",
    title: "Contract",
    chunks: ["Clause 1: parties agree", "Clause 2: payment due May 1"],
  });

  const text = await t.query(internal.knowledge.linesFor, {
    userId,
    sourceId: "d1",
  });
  expect(text).toBe("Clause 1: parties agree\nClause 2: payment due May 1");

  // A different user (even with the same sourceId) sees nothing.
  const stranger = await t.query(internal.knowledge.linesFor, {
    userId: otherUserId,
    sourceId: "d1",
  });
  expect(stranger).toBe("");

  // Unknown sourceId for the right user also returns "".
  const missing = await t.query(internal.knowledge.linesFor, {
    userId,
    sourceId: "does-not-exist",
  });
  expect(missing).toBe("");
});

test("reconstructedSourcesForUser groups a user's chunks per source, ordered by chunkIndex", async () => {
  const t = convexTest(schema);
  const userId = await t.run(async (ctx) => ctx.db.insert("users", {} as any));
  await t.mutation(internal.knowledge.insertChunks, {
    userId, entryId: "e1", source: "document", sourceId: "d1",
    title: "Doc One", chunks: ["alpha", "beta"],
  });
  await t.mutation(internal.knowledge.insertChunks, {
    userId, entryId: "e2", source: "meeting", sourceId: "m1",
    title: "Standup", chunks: ["gamma"],
  });

  const sources = await t.run((ctx) => reconstructedSourcesForUser(ctx, userId));
  const byId = Object.fromEntries(sources.map((s) => [s.sourceId, s]));
  expect(byId["d1"]).toMatchObject({ title: "Doc One", source: "document", text: "alpha\nbeta" });
  expect(byId["m1"]).toMatchObject({ title: "Standup", source: "meeting", text: "gamma" });
});

test("corpusForUser is scoped to the caller — a stranger sees none of it", async () => {
  const t = convexTest(schema);
  const userId = await t.run(async (ctx) => ctx.db.insert("users", {} as any));
  const other = await t.run(async (ctx) => ctx.db.insert("users", {} as any));
  await t.mutation(internal.knowledge.insertChunks, {
    userId, entryId: "e1", source: "document", sourceId: "d1",
    title: "Doc One", chunks: ["alpha", "beta"],
  });

  const mine = await t.query(internal.knowledge.corpusForUser, { userId });
  expect(mine.map((s) => s.sourceId)).toEqual(["d1"]);
  const theirs = await t.query(internal.knowledge.corpusForUser, { userId: other });
  expect(theirs).toEqual([]);
});

test("lineCountsForUser counts reconstructed lines per source", async () => {
  const t = convexTest(schema);
  const userId = await t.run(async (ctx) => ctx.db.insert("users", {} as any));
  await t.mutation(internal.knowledge.insertChunks, {
    userId, entryId: "e1", source: "document", sourceId: "d1",
    title: "Doc One", chunks: ["one\ntwo", "three"], // joins to "one\ntwo\nthree" → 3 lines
  });

  const counts = await t.run((ctx) => lineCountsForUser(ctx, userId));
  expect(counts["d1"]).toBe(3);
});
