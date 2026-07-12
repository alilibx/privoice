import { convexTest } from "convex-test";
import { expect, test } from "vitest";
import schema from "./schema";
import { internal } from "./_generated/api";
import { bm25Search } from "./knowledge";

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
