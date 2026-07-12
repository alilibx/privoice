// Unit tests for the searchDocuments/searchMeetings agent tools' userId
// resolution — the single most security-critical piece of C2 Task 2: these
// tools must always scope to the AUTHENTICATED CALLER's userId (injected by
// the agent runtime onto `ctx.userId`, see chat.ts's `sendMessage` and
// createTool.js's `wrapTools`), and must never accept or derive a userId
// from the model/tool-call input (the input schemas below have no `userId`
// field at all).
//
// These call `tool.execute` directly (bypassing the full agent/LLM runtime,
// which convex-test cannot run headlessly — see documents.test.ts's ./rag
// mock for the same constraint) by replicating exactly what
// @convex-dev/agent's `wrapTools` does at generation time: spread a `ctx`
// (carrying `userId`) onto the tool object, then invoke `execute` as a
// method so `this.ctx` resolves to it.
import { beforeEach, expect, test, vi } from "vitest";
import { searchDocuments, searchMeetings } from "./tools";

beforeEach(() => {
  vi.clearAllMocks();
});

const { ragSearchMock } = vi.hoisted(() => ({
  ragSearchMock: vi.fn(
    async (_ctx: unknown, args: { userId: string; query: string }) => ({
      text: `docs-for:${args.userId}:${args.query}`,
      results: [],
      entries: [],
      usage: {},
    }),
  ),
}));
vi.mock("./rag", () => ({ ragSearch: ragSearchMock }));

function withCtx(ctx: Record<string, unknown>) {
  return { ...searchDocuments, ctx } as typeof searchDocuments & {
    ctx: unknown;
  };
}

test("searchDocuments scopes ragSearch to ctx.userId, never a client-supplied id", async () => {
  const tool = withCtx({ userId: "alice_id" });
  const result = await tool.execute!(
    { query: "roadmap" },
    { toolCallId: "t1", messages: [] } as any,
  );
  expect(ragSearchMock).toHaveBeenCalledWith(
    expect.anything(),
    { userId: "alice_id", query: "roadmap" },
  );
  expect(result).toBe("docs-for:alice_id:roadmap");
});

test("searchDocuments fails closed when ctx carries no userId", async () => {
  const tool = { ...searchDocuments, ctx: {} } as typeof searchDocuments & {
    ctx: unknown;
  };
  await expect(
    tool.execute!({ query: "x" }, { toolCallId: "t2", messages: [] } as any),
  ).rejects.toThrow();
  expect(ragSearchMock).not.toHaveBeenCalled();
});

test("searchMeetings runs the internal query scoped to ctx.userId", async () => {
  const runQuery = vi.fn(async (_ref: unknown, args: { userId: string; query: string }) => [
    { title: `Sync for ${args.userId}`, notes: "notes" },
  ]);
  const tool = {
    ...searchMeetings,
    ctx: { userId: "bob_id", runQuery },
  } as typeof searchMeetings & { ctx: unknown };
  const result = await tool.execute!(
    { query: "sync" },
    { toolCallId: "t3", messages: [] } as any,
  );
  expect(runQuery).toHaveBeenCalledTimes(1);
  const [, args] = runQuery.mock.calls[0];
  expect(args).toEqual({ userId: "bob_id", query: "sync" });
  expect(result).toContain("Sync for bob_id");
});

test("searchMeetings fails closed when ctx carries no userId", async () => {
  const runQuery = vi.fn();
  const tool = {
    ...searchMeetings,
    ctx: { runQuery },
  } as typeof searchMeetings & { ctx: unknown };
  await expect(
    tool.execute!({ query: "x" }, { toolCallId: "t4", messages: [] } as any),
  ).rejects.toThrow();
  expect(runQuery).not.toHaveBeenCalled();
});
