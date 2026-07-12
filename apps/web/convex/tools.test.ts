// Unit tests for the searchKnowledge/pinpoint agent tools' userId
// resolution — the single most security-critical piece of Retrieval v2's
// Task 7: these tools must always scope to the AUTHENTICATED CALLER's
// userId (injected by the agent runtime onto `ctx.userId`, see chat.ts's
// `sendMessage` and createTool.js's `wrapTools`), and must never accept or
// derive a userId from the model/tool-call input (the input schemas below
// have no `userId` field at all).
//
// These call `tool.execute` directly (bypassing the full agent/LLM runtime,
// which convex-test cannot run headlessly — see documents.test.ts's ./rag
// mock for the same constraint) by replicating exactly what
// @convex-dev/agent's `wrapTools` does at generation time: spread a `ctx`
// (carrying `userId`) onto the tool object, then invoke `execute` as a
// method so `this.ctx` resolves to it.
import { beforeEach, expect, test, vi } from "vitest";
import { searchKnowledge, pinpoint } from "./tools";

beforeEach(() => {
  vi.clearAllMocks();
});

const { retrieveMock } = vi.hoisted(() => ({
  retrieveMock: vi.fn(
    async (
      _ctx: unknown,
      args: { userId: string; query: string; source?: string; pinnedSourceIds: string[] },
    ) => ({
      pack: `pack-for:${args.userId}:${args.query}`,
      sources: [{ sourceId: "doc1", title: "Doc One", source: "document" }],
    }),
  ),
}));
vi.mock("./retrieval/retrieve", () => ({ retrieve: retrieveMock }));

function withCtx<T extends object>(tool: T, ctx: Record<string, unknown>) {
  return { ...tool, ctx } as T & { ctx: unknown };
}

test("searchKnowledge scopes retrieve to ctx.userId, never a client-supplied id, and forwards the caller's pins from internal.chat.getPins", async () => {
  const runQuery = vi.fn(async (_ref: unknown, _args: { userId: string }) => [
    "pinned-doc-1",
  ]);
  const tool = withCtx(searchKnowledge, { userId: "alice_id", runQuery });
  const result = await tool.execute!(
    { query: "roadmap" },
    { toolCallId: "t1", messages: [] } as any,
  );
  // getPins is queried scoped to the same authenticated caller, never a
  // client-supplied id.
  expect(runQuery).toHaveBeenCalledTimes(1);
  const [, getPinsArgs] = runQuery.mock.calls[0];
  expect(getPinsArgs).toEqual({ userId: "alice_id" });

  expect(retrieveMock).toHaveBeenCalledWith(expect.anything(), {
    userId: "alice_id",
    query: "roadmap",
    source: undefined,
    pinnedSourceIds: ["pinned-doc-1"],
  });
  expect(result).toContain("pack-for:alice_id:roadmap");
  expect(result).toContain("<<<SOURCES>>>");
  expect(result).toContain(JSON.stringify([{ sourceId: "doc1", title: "Doc One", source: "document" }]));
});

test("searchKnowledge fails closed when ctx carries no userId", async () => {
  const runQuery = vi.fn();
  const tool = withCtx(searchKnowledge, { runQuery });
  await expect(
    tool.execute!({ query: "x" }, { toolCallId: "t2", messages: [] } as any),
  ).rejects.toThrow();
  expect(retrieveMock).not.toHaveBeenCalled();
  expect(runQuery).not.toHaveBeenCalled();
});

test("pinpoint scopes its runQuery to ctx.userId", async () => {
  const runQuery = vi.fn(
    async (_ref: unknown, _args: { userId: string; sourceId: string }) =>
      `line one\nline two\nDate: 2024-05-01\nline four\nline five`,
  );
  const tool = withCtx(pinpoint, { userId: "bob_id", runQuery });
  const result = await tool.execute!(
    { sourceId: "doc1", pattern: "Date:" },
    { toolCallId: "t3", messages: [] } as any,
  );
  expect(runQuery).toHaveBeenCalledTimes(1);
  const [, args] = runQuery.mock.calls[0];
  expect(args).toEqual({ userId: "bob_id", sourceId: "doc1" });
  expect(result).toContain("Date: 2024-05-01");
});

test("pinpoint returns a friendly message when nothing matches", async () => {
  const runQuery = vi.fn(async () => "line one\nline two\nline three");
  const tool = withCtx(pinpoint, { userId: "bob_id", runQuery });
  const result = await tool.execute!(
    { sourceId: "doc1", pattern: "nomatch-xyz" },
    { toolCallId: "t4", messages: [] } as any,
  );
  expect(result).toBe("No matches found.");
});

test("pinpoint returns a friendly message for an invalid regex pattern", async () => {
  const runQuery = vi.fn(async () => "line one\nline two");
  const tool = withCtx(pinpoint, { userId: "bob_id", runQuery });
  const result = await tool.execute!(
    { sourceId: "doc1", pattern: "(unterminated" },
    { toolCallId: "t5", messages: [] } as any,
  );
  expect(result).toBe("Invalid search pattern.");
});

test("pinpoint rejects an over-long pattern before compiling or querying (ReDoS hardening)", async () => {
  const runQuery = vi.fn(async () => "line one\nline two");
  const tool = withCtx(pinpoint, { userId: "bob_id", runQuery });
  const longPattern = "a".repeat(201);
  const result = await tool.execute!(
    { sourceId: "doc1", pattern: longPattern },
    { toolCallId: "t7", messages: [] } as any,
  );
  expect(result).toBe("Search pattern too long.");
  // Cheap: rejected before ever touching the DB.
  expect(runQuery).not.toHaveBeenCalled();
});

test("pinpoint fails closed when ctx carries no userId", async () => {
  const runQuery = vi.fn();
  const tool = withCtx(pinpoint, { runQuery });
  await expect(
    tool.execute!({ sourceId: "doc1", pattern: "x" }, { toolCallId: "t6", messages: [] } as any),
  ).rejects.toThrow();
  expect(runQuery).not.toHaveBeenCalled();
});

test("listDocuments scopes to ctx.userId and formats the inventory", async () => {
  const runQuery = vi.fn(async (_ref: unknown, _args: { userId: string }) => [
    { filename: "a.pdf", kind: "pdf", status: "ready", sizeBytes: 2048, createdAt: 1 },
    { filename: "b.txt", kind: "txt", status: "parsing", sizeBytes: 10, createdAt: 2 },
  ]);
  const { listDocuments } = await import("./tools");
  const tool = withCtx(listDocuments, { userId: "alice_id", runQuery });
  const result = await tool.execute!({}, { toolCallId: "t1", messages: [] } as any);

  const [, args] = runQuery.mock.calls[0];
  expect(args).toEqual({ userId: "alice_id" });
  expect(result).toContain("a.pdf");
  expect(result).toContain("b.txt");
  expect(result).toContain("parsing");
});

test("listDocuments fails closed without a caller in scope", async () => {
  const { listDocuments } = await import("./tools");
  const tool = withCtx(listDocuments, {});
  await expect(
    tool.execute!({}, { toolCallId: "t1", messages: [] } as any),
  ).rejects.toThrow(/authenticated user/i);
});
