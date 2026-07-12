// Unit tests for the searchKnowledge/grep agent tools' userId
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
import { searchKnowledge, grep } from "./tools";

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

test("grep (scoped) returns matched line + context, numbered, scoped to ctx.userId", async () => {
  const runQuery = vi.fn(
    async (_ref: unknown, _args: { userId: string; sourceId: string }) =>
      "line one\nline two\nDate: 2024-05-01\nline four\nline five",
  );
  const tool = withCtx(grep, { userId: "bob_id", runQuery });
  const result = await tool.execute!(
    { pattern: "Date:", sourceId: "d1" },
    { toolCallId: "g1", messages: [] } as any,
  );
  const [, args] = runQuery.mock.calls[0];
  expect(args).toEqual({ userId: "bob_id", sourceId: "d1" });
  expect(result).toContain("Date: 2024-05-01");
  expect(result).toContain("3  Date: 2024-05-01"); // line number present
  expect(result).toContain("d1:"); // coordinate header
});

test("grep (corpus) searches all sources and labels each hit with title:line", async () => {
  const runQuery = vi.fn(async (_ref: unknown, _args: { userId: string }) => [
    { sourceId: "d1", title: "Contract A", source: "document", text: "foo\nindemnity clause\nbar" },
    { sourceId: "d2", title: "Contract B", source: "document", text: "nothing here" },
    { sourceId: "d3", title: "Contract C", source: "document", text: "more indemnity talk" },
  ]);
  const tool = withCtx(grep, { userId: "bob_id", runQuery });
  const result = await tool.execute!(
    { pattern: "indemnity" },
    { toolCallId: "g2", messages: [] } as any,
  );
  const [, args] = runQuery.mock.calls[0];
  expect(args).toEqual({ userId: "bob_id" });
  expect(result).toContain("Contract A:");
  expect(result).toContain("indemnity clause");
  expect(result).toContain("Contract C:");
  expect(result).not.toContain("Contract B:"); // no match there
});

test("grep returns a friendly message when nothing matches", async () => {
  const runQuery = vi.fn(async () => [
    { sourceId: "d1", title: "Doc", source: "document", text: "alpha\nbeta" },
  ]);
  const tool = withCtx(grep, { userId: "bob_id", runQuery });
  const result = await tool.execute!(
    { pattern: "nomatch-xyz" },
    { toolCallId: "g3", messages: [] } as any,
  );
  expect(result).toBe("No matches found.");
});

test("grep returns a friendly message for an invalid regex", async () => {
  const runQuery = vi.fn(async () => [
    { sourceId: "d1", title: "Doc", source: "document", text: "alpha" },
  ]);
  const tool = withCtx(grep, { userId: "bob_id", runQuery });
  const result = await tool.execute!(
    { pattern: "(unterminated" },
    { toolCallId: "g4", messages: [] } as any,
  );
  expect(result).toBe("Invalid search pattern.");
});

test("grep rejects an over-long pattern before compiling or querying (ReDoS hardening)", async () => {
  const runQuery = vi.fn();
  const tool = withCtx(grep, { userId: "bob_id", runQuery });
  const result = await tool.execute!(
    { pattern: "a".repeat(201) },
    { toolCallId: "g5", messages: [] } as any,
  );
  expect(result).toBe("Search pattern too long.");
  expect(runQuery).not.toHaveBeenCalled();
});

test("grep fails closed when ctx carries no userId", async () => {
  const runQuery = vi.fn();
  const tool = withCtx(grep, { runQuery });
  await expect(
    tool.execute!({ pattern: "x" }, { toolCallId: "g6", messages: [] } as any),
  ).rejects.toThrow(/authenticated user/i);
  expect(runQuery).not.toHaveBeenCalled();
});

test("listDocuments scopes to ctx.userId and formats the inventory with id handle + line count", async () => {
  const runQuery = vi.fn(async (_ref: unknown, _args: { userId: string }) => [
    { sourceId: "doc_a", filename: "a.pdf", kind: "pdf", status: "ready", sizeBytes: 2048, lineCount: 12, createdAt: 1 },
    { sourceId: "doc_b", filename: "b.txt", kind: "txt", status: "parsing", sizeBytes: 10, lineCount: 0, createdAt: 2 },
  ]);
  const { listDocuments } = await import("./tools");
  const tool = withCtx(listDocuments, { userId: "alice_id", runQuery });
  const result = await tool.execute!({}, { toolCallId: "t1", messages: [] } as any);

  const [, args] = runQuery.mock.calls[0];
  expect(args).toEqual({ userId: "alice_id" });
  expect(result).toContain("a.pdf");
  expect(result).toContain("12 lines");
  expect(result).toContain("doc_a"); // id handle present
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

test("readDocument returns just line 1, numbered, with a range header (first-line case)", async () => {
  const runQuery = vi.fn(
    async (_ref: unknown, _args: { userId: string; sourceId: string }) =>
      "first line\nsecond line\nthird line",
  );
  const { readDocument } = await import("./tools");
  const tool = withCtx(readDocument, { userId: "alice_id", runQuery });
  const result = await tool.execute!(
    { sourceId: "d1", startLine: 1, maxLines: 1 },
    { toolCallId: "r1", messages: [] } as any,
  );
  const [, args] = runQuery.mock.calls[0];
  expect(args).toEqual({ userId: "alice_id", sourceId: "d1" });
  expect(result).toContain("lines 1–1 of 3:");
  expect(result).toContain("1  first line");
  expect(result).not.toContain("second line");
});

test("readDocument returns the requested window with correct numbering", async () => {
  const runQuery = vi.fn(async () => "a\nb\nc\nd\ne");
  const { readDocument } = await import("./tools");
  const tool = withCtx(readDocument, { userId: "alice_id", runQuery });
  const result = await tool.execute!(
    { sourceId: "d1", startLine: 2, maxLines: 2 },
    { toolCallId: "r2", messages: [] } as any,
  );
  expect(result).toContain("2  b");
  expect(result).toContain("3  c");
  expect(result).not.toContain("4  d");
});

test("readDocument clamps maxLines above the ceiling and coerces startLine below 1", async () => {
  const runQuery = vi.fn(async () => Array.from({ length: 500 }, (_, i) => `L${i + 1}`).join("\n"));
  const { readDocument } = await import("./tools");
  const tool = withCtx(readDocument, { userId: "alice_id", runQuery });
  const result = await tool.execute!(
    { sourceId: "d1", startLine: 0, maxLines: 9999 },
    { toolCallId: "r3", messages: [] } as any,
  );
  expect(result).toContain("lines 1–200 of 500:");
  expect(result).toContain("1  L1");
  expect(result).toContain("200  L200");
  expect(result).not.toContain("201  L201");
});

test("readDocument reports when startLine is past the end", async () => {
  const runQuery = vi.fn(async () => "only\ntwo");
  const { readDocument } = await import("./tools");
  const tool = withCtx(readDocument, { userId: "alice_id", runQuery });
  const result = await tool.execute!(
    { sourceId: "d1", startLine: 5 },
    { toolCallId: "r4", messages: [] } as any,
  );
  expect(result).toBe("Document has only 2 lines.");
});

test("readDocument truncates output past the char cap", async () => {
  const giant = "x".repeat(20000);
  const runQuery = vi.fn(async () => giant);
  const { readDocument } = await import("./tools");
  const tool = withCtx(readDocument, { userId: "alice_id", runQuery });
  const result = (await tool.execute!(
    { sourceId: "d1" },
    { toolCallId: "r5", messages: [] } as any,
  )) as string;
  expect(result.length).toBeLessThanOrEqual(8192 + "\n… (truncated)".length);
  expect(result.endsWith("… (truncated)")).toBe(true);
});

test("readDocument returns a friendly message for an empty/missing document", async () => {
  const runQuery = vi.fn(async () => "");
  const { readDocument } = await import("./tools");
  const tool = withCtx(readDocument, { userId: "alice_id", runQuery });
  const result = await tool.execute!(
    { sourceId: "nope" },
    { toolCallId: "r6", messages: [] } as any,
  );
  expect(result).toBe("No content found for that document.");
});

test("readDocument fails closed without a caller in scope", async () => {
  const runQuery = vi.fn();
  const { readDocument } = await import("./tools");
  const tool = withCtx(readDocument, { runQuery });
  await expect(
    tool.execute!({ sourceId: "d1" }, { toolCallId: "r7", messages: [] } as any),
  ).rejects.toThrow(/authenticated user/i);
  expect(runQuery).not.toHaveBeenCalled();
});
