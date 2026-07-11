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
import { api } from "./_generated/api";

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
  // would actually fire and run the "use node" ingestDocument action (hitting
  // the real embedding pipeline, with no API key in test env) shortly after
  // this test returns — producing an unhandled "Write outside of transaction"
  // rejection that fails the whole run. Freeze the clock so the scheduled
  // callback never fires; we only assert that it was queued, not that it ran.
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

test("remove refuses another user's doc and cascades chunks", async () => {
  const t = convexTest(schema, modules);
  const { t: alice, userId: aId } = await asNewUser(t, "a@x.com");
  const { t: bob } = await asNewUser(t, "b@x.com");
  const docId = await t.run(async (ctx) => {
    const id = await ctx.db.insert("documents", {
      userId: aId, storageId: (await ctx.storage.store(new Blob(["x"]))) as any,
      filename: "a.txt", mimeType: "t", kind: "txt", sizeBytes: 1,
      status: "ready", chunkCount: 1, createdAt: 0,
    });
    await ctx.db.insert("documentChunks", {
      userId: aId, documentId: id, chunkIndex: 0, text: "x", embedding: [0.1],
    });
    return id;
  });
  await expect(bob.mutation(api.documents.remove, { id: docId })).rejects.toThrow();
  await alice.mutation(api.documents.remove, { id: docId });
  const remaining = await t.run((ctx) => ctx.db.query("documentChunks").collect());
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
