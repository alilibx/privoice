import { convexTest } from "convex-test";
import { expect, test, vi, beforeEach, afterEach } from "vitest";
import schema from "./schema";
import { api } from "./_generated/api";

// meetings.ts's `create` schedules ingestMeeting (an internalAction), and
// `remove` calls ragRemoveSource — both from ./rag.ts, which constructs a
// real @convex-dev/rag component client and (when its methods are actually
// invoked) calls OpenRouter over the network for embeddings. convex-test
// can't run that component headlessly, so mock the whole module: this lets
// us assert *how* meetings.ts drives rag (namespace=userId, key=meetingId,
// source="meeting") without exercising the real component or hitting the
// network.
const { ragAddMock, ragRemoveSourceMock } = vi.hoisted(() => ({
  ragAddMock: vi.fn(
    async (
      _ctx: unknown,
      _args: { userId: string; source: string; sourceId: string; title: string; text: string },
    ) => ({ entryId: "e1", chunkCount: 1 }),
  ),
  ragRemoveSourceMock: vi.fn(
    async (_ctx: unknown, _args: { userId: string; source: string; sourceId: string }) => {},
  ),
}));
vi.mock("./rag", () => ({
  ragAdd: ragAddMock,
  ragRemoveSource: ragRemoveSourceMock,
  ragSearch: vi.fn(async () => ({ results: [], text: "", entries: [], usage: {} })),
  rag: {},
}));

// convex-test loads all backend modules from this glob.
const modules = import.meta.glob("./**/*.ts");

// `create` schedules ingestMeeting via `ctx.scheduler.runAfter(0, ...)`,
// which convex-test backs with a real `setTimeout`. If we let that fire on
// the real clock, it fires asynchronously (on a later event-loop turn) and
// leaks into whichever test happens to be running at that point, polluting
// ragAddMock's call count across tests. Fake timers on every test (no test
// here needs real ones) mean a scheduled call only ever runs when a test
// explicitly flushes it via `t.finishAllScheduledFunctions(vi.runAllTimers)`
// — so tests that don't care about ingestion just leave it unflushed.
beforeEach(() => {
  vi.useFakeTimers();
  ragAddMock.mockClear();
  ragRemoveSourceMock.mockClear();
});
afterEach(() => {
  vi.useRealTimers();
});

// Seed a user row and return an identity whose subject matches what
// getAuthUserId expects (`${userId}|${sessionId}`).
async function asNewUser(t: ReturnType<typeof convexTest>, email: string) {
  const userId = await t.run(async (ctx) => ctx.db.insert("users", { email }));
  return t.withIdentity({ subject: `${userId}|session_${userId}` });
}

test("create then list returns only the caller's meetings", async () => {
  const t = convexTest(schema, modules);
  const alice = await asNewUser(t, "alice@example.com");
  await alice.mutation(api.meetings.create, { title: "Alice sync" });
  const rows = await alice.query(api.meetings.list, {});
  expect(rows).toHaveLength(1);
  expect(rows[0].title).toBe("Alice sync");
});

test("a user never sees another user's meetings", async () => {
  const t = convexTest(schema, modules);
  const alice = await asNewUser(t, "alice@example.com");
  const bob = await asNewUser(t, "bob@example.com");
  await alice.mutation(api.meetings.create, { title: "Alice private" });
  expect(await bob.query(api.meetings.list, {})).toHaveLength(0);
});

test("remove refuses another user's meeting", async () => {
  const t = convexTest(schema, modules);
  const alice = await asNewUser(t, "alice@example.com");
  const bob = await asNewUser(t, "bob@example.com");
  const id = await alice.mutation(api.meetings.create, { title: "Alice only" });
  await expect(bob.mutation(api.meetings.remove, { id })).rejects.toThrow();
  expect(await alice.query(api.meetings.list, {})).toHaveLength(1);
});

test("unauthenticated calls throw", async () => {
  const t = convexTest(schema, modules);
  await expect(t.query(api.meetings.list, {})).rejects.toThrow();
  await expect(t.mutation(api.meetings.create, { title: "x" })).rejects.toThrow();
});

test("create schedules ingestMeeting, which calls ragAdd with source/sourceId/title for the meeting", async () => {
  const t = convexTest(schema, modules);
  const alice = await asNewUser(t, "alice@example.com");
  const id = await alice.mutation(api.meetings.create, {
    title: "Roadmap Review",
    notes: "Q3 planning notes",
  });
  const aliceRow = await t.run((ctx) => ctx.db.get(id));

  await t.finishAllScheduledFunctions(vi.runAllTimers);

  expect(ragAddMock).toHaveBeenCalledTimes(1);
  const [, ragArgs] = ragAddMock.mock.calls[0];
  expect(ragArgs).toEqual({
    userId: aliceRow!.userId,
    source: "meeting",
    sourceId: id,
    title: "Roadmap Review",
    text: "Roadmap Review\n\nQ3 planning notes",
  });
});

test("create with no notes still ingests the title alone", async () => {
  const t = convexTest(schema, modules);
  const alice = await asNewUser(t, "alice@example.com");
  await alice.mutation(api.meetings.create, { title: "No notes here" });

  await t.finishAllScheduledFunctions(vi.runAllTimers);

  expect(ragAddMock).toHaveBeenCalledTimes(1);
  const [, ragArgs] = ragAddMock.mock.calls[0];
  expect(ragArgs.text).toBe("No notes here");
});

test("remove calls ragRemoveSource with meeting source/sourceId, then deletes the row", async () => {
  const t = convexTest(schema, modules);
  const alice = await asNewUser(t, "alice@example.com");
  const bob = await asNewUser(t, "bob@example.com");
  const id = await alice.mutation(api.meetings.create, { title: "Alice only" });
  const aliceRow = await t.run((ctx) => ctx.db.get(id));

  await expect(bob.mutation(api.meetings.remove, { id })).rejects.toThrow();
  expect(ragRemoveSourceMock).not.toHaveBeenCalled(); // bob's attempt never reaches rag

  await alice.mutation(api.meetings.remove, { id });
  expect(ragRemoveSourceMock).toHaveBeenCalledTimes(1);
  const [, ragArgs] = ragRemoveSourceMock.mock.calls[0];
  expect(ragArgs).toEqual({ userId: aliceRow!.userId, source: "meeting", sourceId: id });

  const remaining = await t.run((ctx) => ctx.db.get(id));
  expect(remaining).toBeNull();
});
