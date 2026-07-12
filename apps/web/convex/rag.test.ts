// documents.test.ts fully mocks "./rag" and only exercises documents.ts's
// call sites (namespace/source/sourceId args passed to ragRemoveSource) plus
// the (unmocked) knowledgeChunks mirror mutations directly. That leaves
// ragAdd's chunk/entryId alignment and the ctx.runMutation mirror calls in
// this file completely uncovered. This suite imports the real ragAdd /
// ragRemoveSource and spies on the underlying `rag` component client's
// methods (add/getNamespace/deleteByKeyAsync) so no network/embeddings run,
// while asserting exactly how ragAdd/ragRemoveSource drive both the rag
// component and the knowledgeChunks mirror (internal.knowledge.insertChunks /
// deleteBySource) via a fake ctx.
import { expect, test, vi, afterEach } from "vitest";
import { rag, ragAdd, ragRemoveSource } from "./rag";
import { internal } from "./_generated/api";
import { getFunctionName } from "convex/server";
import type { ActionCtx, MutationCtx } from "./_generated/server";

afterEach(() => {
  vi.restoreAllMocks();
});

const LONG_TEXT = Array.from(
  { length: 8 },
  (_, i) => `Paragraph ${i}: ${"Revenue grew twelve percent this quarter. ".repeat(20)}`,
).join("\n\n");

test("ragAdd: forwards namespace/key/title/filters to rag.add, mirrors the SAME chunks into insertChunks, and returns entryId+chunkCount", async () => {
  const addSpy = vi.spyOn(rag, "add").mockResolvedValue({ entryId: "entry_1" } as any);
  const runMutation = vi.fn().mockResolvedValue(undefined);
  const fakeCtx = { runMutation } as unknown as ActionCtx;

  const result = await ragAdd(fakeCtx, {
    userId: "u1",
    source: "document",
    sourceId: "d1",
    title: "Q3",
    text: LONG_TEXT,
  });

  expect(addSpy).toHaveBeenCalledTimes(1);
  const addArgs = addSpy.mock.calls[0][1] as any;
  expect(addArgs.namespace).toBe("u1");
  expect(addArgs.key).toBe("d1");
  expect(addArgs.title).toBe("Q3");
  expect(addArgs.filterValues).toEqual(
    expect.arrayContaining([
      { name: "source", value: "document" },
      { name: "sourceId", value: "d1" },
    ]),
  );
  expect(Array.isArray(addArgs.chunks)).toBe(true);
  expect(addArgs.chunks.length).toBeGreaterThan(1); // long input actually chunked

  // Idempotent re-ingest: the mirror must be REPLACED, not appended to —
  // deleteBySource runs before insertChunks so re-ingesting the same
  // sourceId (e.g. meetings:backfill) never duplicates knowledgeChunks rows
  // or orphans stale ones.
  expect(runMutation).toHaveBeenCalledTimes(2);
  const [deleteRef, deleteArgs] = runMutation.mock.calls[0];
  expect(getFunctionName(deleteRef)).toBe(getFunctionName(internal.knowledge.deleteBySource));
  expect(deleteArgs).toEqual({ userId: "u1", source: "document", sourceId: "d1" });

  const [insertRef, mirrorArgs] = runMutation.mock.calls[1];
  expect(getFunctionName(insertRef)).toBe(getFunctionName(internal.knowledge.insertChunks));
  // Alignment: the exact same chunks array/content passed to rag.add is what
  // gets mirrored into knowledgeChunks.
  expect(mirrorArgs.chunks).toBe(addArgs.chunks);
  expect(mirrorArgs).toMatchObject({
    entryId: "entry_1",
    source: "document",
    sourceId: "d1",
    title: "Q3",
  });

  expect(result).toEqual({ entryId: "entry_1", chunkCount: addArgs.chunks.length });
});

test("ragRemoveSource: deletes the rag entry by key and mirrors deleteBySource", async () => {
  const getNamespaceSpy = vi
    .spyOn(rag, "getNamespace")
    .mockResolvedValue({ namespaceId: "ns1" } as any);
  const deleteByKeyAsyncSpy = vi.spyOn(rag, "deleteByKeyAsync").mockResolvedValue(undefined as any);
  const runMutation = vi.fn().mockResolvedValue(undefined);
  const fakeCtx = { runMutation } as unknown as MutationCtx;

  await ragRemoveSource(fakeCtx, { userId: "u1", source: "document", sourceId: "d1" });

  expect(getNamespaceSpy).toHaveBeenCalledWith(fakeCtx, { namespace: "u1" });
  expect(deleteByKeyAsyncSpy).toHaveBeenCalledWith(fakeCtx, { namespaceId: "ns1", key: "d1" });

  expect(runMutation).toHaveBeenCalledTimes(1);
  const [ref, mirrorArgs] = runMutation.mock.calls[0];
  expect(getFunctionName(ref)).toBe(getFunctionName(internal.knowledge.deleteBySource));
  expect(mirrorArgs).toEqual({ userId: "u1", source: "document", sourceId: "d1" });
});

test("ragRemoveSource: no namespace yet -> skips deleteByKeyAsync but still mirrors deleteBySource", async () => {
  const getNamespaceSpy = vi.spyOn(rag, "getNamespace").mockResolvedValue(null);
  const deleteByKeyAsyncSpy = vi.spyOn(rag, "deleteByKeyAsync").mockResolvedValue(undefined as any);
  const runMutation = vi.fn().mockResolvedValue(undefined);
  const fakeCtx = { runMutation } as unknown as MutationCtx;

  await ragRemoveSource(fakeCtx, { userId: "u1", source: "document", sourceId: "d1" });

  expect(getNamespaceSpy).toHaveBeenCalledWith(fakeCtx, { namespace: "u1" });
  expect(deleteByKeyAsyncSpy).not.toHaveBeenCalled();

  expect(runMutation).toHaveBeenCalledTimes(1);
  const [ref, mirrorArgs] = runMutation.mock.calls[0];
  expect(getFunctionName(ref)).toBe(getFunctionName(internal.knowledge.deleteBySource));
  expect(mirrorArgs).toEqual({ userId: "u1", source: "document", sourceId: "d1" });
});
