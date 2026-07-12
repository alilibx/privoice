// This suite exercises convex-test's storage.store(), which needs a real
// Blob#arrayBuffer(). The project's default vitest environment is jsdom,
// whose Blob polyfill doesn't implement arrayBuffer()/text()/stream() (only
// slice/size/type), so convex-test's internal hashing throws "blob.arrayBuffer
// is not a function". Force node's environment for this file only so the
// global Blob is the real one; other suites keep jsdom via vitest.config.ts.
// @vitest-environment node
import { convexTest } from "convex-test";
import { expect, test, vi } from "vitest";
import schema from "./schema";
import { api, internal } from "./_generated/api";

// documents.ts (`remove`) calls ragRemoveSource, and ingest.ts's scheduled
// action calls ragAdd — both from ./rag.ts, which constructs a real
// @convex-dev/rag component client and (when its methods are actually
// invoked) calls OpenRouter over the network for embeddings. convex-test
// can't run that component headlessly, so mock the whole module: this lets
// us assert *how* documents.ts drives rag (namespace=userId, key=documentId,
// source="document") without exercising the real component or hitting the
// network. The `knowledgeChunks` mirror writes (insertChunks/deleteBySource)
// live in ./knowledge.ts, which is NOT mocked — those run for real.
const { ragRemoveSourceMock } = vi.hoisted(() => ({
  ragRemoveSourceMock: vi.fn(
    async (_ctx: unknown, _args: { userId: string; source: string; sourceId: string }) => {},
  ),
}));
vi.mock("./rag", () => ({
  ragRemoveSource: ragRemoveSourceMock,
  ragAdd: vi.fn(async () => ({ entryId: "e1", chunkCount: 2 })),
  rag: {},
}));

const modules = import.meta.glob("./**/*.ts");

async function asNewUser(t: ReturnType<typeof convexTest>, email: string) {
  const userId = await t.run((ctx) => ctx.db.insert("users", { email }));
  return { t: t.withIdentity({ subject: `${userId}|s_${userId}` }), userId };
}
// convex-test validates v.id("_storage") fields for real, so an arbitrary
// string like "x" is rejected at insert time (unlike a live Convex backend,
// which would just fail later on read). Where a test needs a document row
// with a storageId but never reads the blob, we still store a tiny real blob
// via ctx.storage.store() to get a valid id.

test("create rejects oversize + unsupported, schedules ingest on success", async () => {
  // convex-test's scheduler.runAfter uses a real setTimeout internally, which
  // would actually fire and run the "use node" ingestDocument action shortly
  // after this test returns — producing an unhandled "Write outside of
  // transaction" rejection that fails the whole run. Freeze the clock so the
  // scheduled callback never fires; we only assert that it was queued, not
  // that it ran.
  vi.useFakeTimers();
  try {
    const t = convexTest(schema, modules);
    const { t: alice } = await asNewUser(t, "a@x.com");
    const storageId = await alice.run(async (ctx) =>
      ctx.storage.store(new Blob(["hello"], { type: "text/plain" })),
    );
    await expect(
      alice.mutation(api.documents.create, {
        storageId, filename: "big.pdf", mimeType: "application/pdf", sizeBytes: 20_000_000,
      }),
    ).rejects.toThrow();
    await expect(
      alice.mutation(api.documents.create, {
        storageId, filename: "note.exe", mimeType: "x", sizeBytes: 10,
      }),
    ).rejects.toThrow();
    const id = await alice.mutation(api.documents.create, {
      storageId, filename: "note.txt", mimeType: "text/plain", sizeBytes: 5,
    });
    expect(id).toBeDefined();
    // scheduled function is queued (not run — see comment above)
    const scheduled = await t.run((ctx) => ctx.db.system.query("_scheduled_functions").collect());
    expect(scheduled.length).toBeGreaterThan(0);
  } finally {
    vi.useRealTimers();
  }
});

test("list is isolated per user", async () => {
  const t = convexTest(schema, modules);
  const { t: alice, userId: aId } = await asNewUser(t, "a@x.com");
  const { t: bob } = await asNewUser(t, "b@x.com");
  await t.run(async (ctx) => {
    const storageId = await ctx.storage.store(new Blob(["x"]));
    await ctx.db.insert("documents", {
      userId: aId, storageId, filename: "a.txt", mimeType: "t",
      kind: "txt", sizeBytes: 1, status: "ready", chunkCount: 0, createdAt: 0,
    });
  });
  expect(await alice.query(api.documents.list, {})).toHaveLength(1);
  expect(await bob.query(api.documents.list, {})).toHaveLength(0);
});

test("remove refuses another user's doc, deletes the row, and calls ragRemoveSource with userId namespace + document source/sourceId", async () => {
  const t = convexTest(schema, modules);
  const { t: alice, userId: aId } = await asNewUser(t, "a@x.com");
  const { t: bob } = await asNewUser(t, "b@x.com");
  const docId = await t.run(async (ctx) =>
    ctx.db.insert("documents", {
      userId: aId, storageId: (await ctx.storage.store(new Blob(["x"]))) as any,
      filename: "a.txt", mimeType: "t", kind: "txt", sizeBytes: 1,
      status: "ready", chunkCount: 1, createdAt: 0,
    }),
  );

  await expect(bob.mutation(api.documents.remove, { id: docId })).rejects.toThrow();
  expect(ragRemoveSourceMock).not.toHaveBeenCalled(); // bob's attempt never reaches rag

  await alice.mutation(api.documents.remove, { id: docId });
  expect(ragRemoveSourceMock).toHaveBeenCalledTimes(1);
  const [, ragArgs] = ragRemoveSourceMock.mock.calls[0];
  // namespace=userId, source="document", sourceId=documentId
  expect(ragArgs).toEqual({ userId: aId, source: "document", sourceId: docId });

  const remaining = await t.run((ctx) => ctx.db.get(docId));
  expect(remaining).toBeNull();
});

test("knowledgeChunks mirror: insertChunks seeds rows, deleteBySource clears them for a (userId, source, sourceId)", async () => {
  // documents.remove only calls ragRemoveSource (mocked above), so exercising
  // it here would just re-assert the mock was called (already covered by the
  // "remove refuses another user's doc..." test above). ragAdd's and
  // ragRemoveSource's actual driving of these two internal.knowledge
  // mutations — including chunk/entryId alignment — is covered for real,
  // without mocking anything, in rag.test.ts. This test only proves the
  // knowledge.ts mirror mutations themselves work in isolation.
  const t = convexTest(schema, modules);
  const { userId: aId } = await asNewUser(t, "a@x.com");
  const docId = await t.run(async (ctx) =>
    ctx.db.insert("documents", {
      userId: aId, storageId: (await ctx.storage.store(new Blob(["x"]))) as any,
      filename: "a.txt", mimeType: "t", kind: "txt", sizeBytes: 1,
      status: "ready", chunkCount: 2, createdAt: 0,
    }),
  );

  await t.mutation(internal.knowledge.insertChunks, {
    userId: aId, entryId: "e1", source: "document", sourceId: docId,
    title: "a.txt", chunks: ["chunk one", "chunk two"],
  });
  const seeded = await t.run((ctx) =>
    ctx.db.query("knowledgeChunks").withIndex("by_source", (q) =>
      q.eq("userId", aId).eq("source", "document").eq("sourceId", docId),
    ).collect(),
  );
  expect(seeded).toHaveLength(2);

  await t.mutation(internal.knowledge.deleteBySource, {
    userId: aId, source: "document", sourceId: docId,
  });
  const remaining = await t.run((ctx) =>
    ctx.db.query("knowledgeChunks").withIndex("by_source", (q) =>
      q.eq("userId", aId).eq("source", "document").eq("sourceId", docId),
    ).collect(),
  );
  expect(remaining).toHaveLength(0);
});

test("unauthenticated calls throw", async () => {
  const t = convexTest(schema, modules);
  await expect(t.query(api.documents.list, {})).rejects.toThrow();
  await expect(
    t.mutation(api.documents.create, {
      storageId: "x" as any, filename: "a.txt", mimeType: "t", sizeBytes: 1,
    }),
  ).rejects.toThrow();
});

test("create persists contentHash when provided", async () => {
  vi.useFakeTimers();
  try {
    const t = convexTest(schema, modules);
    const { t: alice, userId } = await asNewUser(t, "hash@x.com");
    const storageId = await alice.run(async (ctx) =>
      ctx.storage.store(new Blob([new Uint8Array([1, 2, 3])])),
    );
    const id = await alice.mutation(api.documents.create, {
      storageId,
      filename: "a.pdf",
      mimeType: "application/pdf",
      sizeBytes: 3,
      contentHash: "deadbeef",
    });
    const doc = await t.run((ctx) => ctx.db.get(id));
    expect(doc?.contentHash).toBe("deadbeef");
    expect(doc?.userId).toBe(userId);
  } finally {
    vi.useRealTimers();
  }
});

test("listForUser returns only the caller's documents", async () => {
  const t = convexTest(schema, modules);
  const { userId: aliceId } = await asNewUser(t, "alice-list@x.com");
  const { userId: bobId } = await asNewUser(t, "bob-list@x.com");
  await t.run(async (ctx) => {
    const storageId = await ctx.storage.store(new Blob([new Uint8Array([1])]));
    await ctx.db.insert("documents", {
      userId: aliceId, storageId, filename: "a.pdf", mimeType: "application/pdf",
      kind: "pdf", sizeBytes: 1, status: "ready", chunkCount: 1, createdAt: 1,
    });
    await ctx.db.insert("documents", {
      userId: bobId, storageId, filename: "b.pdf", mimeType: "application/pdf",
      kind: "pdf", sizeBytes: 1, status: "ready", chunkCount: 1, createdAt: 1,
    });
  });
  const list = await t.query(internal.documents.listForUser, { userId: aliceId });
  expect(list).toHaveLength(1);
  expect(list[0].filename).toBe("a.pdf");
});
