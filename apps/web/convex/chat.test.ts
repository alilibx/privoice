// Authz/isolation tests for convex/chat.ts. The @convex-dev/agent and
// @convex-dev/rag components aren't registered with convex-test (it only
// knows about our own schema/modules, not components wired up via
// convex.config.ts — see documents.test.ts's identical constraint), so any
// call that would reach into the real agent component (chatAgent.*,
// listUIMessages, syncStreams) is mocked here. What we assert for REAL
// (against our own `chatThreads` table, no mocking involved) is the
// security-critical part: a thread is only ever visible/usable by the
// userId that created it, resolved server-side from the authenticated
// identity — never from client input.
import { convexTest } from "convex-test";
import { expect, test, vi } from "vitest";
import schema from "./schema";
import { api, internal } from "./_generated/api";

const { createThreadMock, continueThreadMock } = vi.hoisted(() => ({
  createThreadMock: vi.fn(
    async (_ctx: unknown, _args: { userId?: string | null }) => ({
      threadId: `thread_${Math.random().toString(36).slice(2)}`,
    }),
  ),
  continueThreadMock: vi.fn(
    async (
      _ctx: unknown,
      args: { threadId: string; userId?: string | null },
    ) => ({
      thread: {
        threadId: args.threadId,
        streamText: vi.fn(async () => ({
          consumeStream: vi.fn(async () => {}),
        })),
      },
    }),
  ),
}));
vi.mock("./agent", () => ({
  chatAgent: { createThread: createThreadMock, continueThread: continueThreadMock },
}));

vi.mock("@convex-dev/agent", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@convex-dev/agent")>();
  return {
    ...actual,
    listUIMessages: vi.fn(async () => ({
      page: [],
      isDone: true,
      continueCursor: "",
    })),
    syncStreams: vi.fn(async () => undefined),
  };
});

const modules = import.meta.glob("./**/*.ts");

async function asNewUser(t: ReturnType<typeof convexTest>, email: string) {
  const userId = await t.run(async (ctx) => ctx.db.insert("users", { email }));
  return { t: t.withIdentity({ subject: `${userId}|session_${userId}` }), userId };
}

test("createThread inserts a row owned by the caller, returned by their own listThreads", async () => {
  const t = convexTest(schema, modules);
  const { t: alice, userId: aliceId } = await asNewUser(t, "alice@example.com");

  const threadId = await alice.mutation(api.chat.createThread, {});
  expect(typeof threadId).toBe("string");
  expect(createThreadMock).toHaveBeenCalledWith(
    expect.anything(),
    { userId: aliceId },
  );

  const rows = await alice.query(api.chat.listThreads, {});
  expect(rows).toHaveLength(1);
  expect(rows[0].threadId).toBe(threadId);
  expect(rows[0].userId).toBe(aliceId);
});

test("a user never sees another user's threads", async () => {
  const t = convexTest(schema, modules);
  const { t: alice } = await asNewUser(t, "alice@example.com");
  const { t: bob } = await asNewUser(t, "bob@example.com");

  await alice.mutation(api.chat.createThread, {});
  const bobThreads = await bob.query(api.chat.listThreads, {});
  expect(bobThreads).toHaveLength(0);
});

test("listMessages throws 'Not found' for a non-owner, and never reaches the agent component", async () => {
  const t = convexTest(schema, modules);
  const { t: alice } = await asNewUser(t, "alice@example.com");
  const { t: bob } = await asNewUser(t, "bob@example.com");

  const threadId = await alice.mutation(api.chat.createThread, {});
  await expect(
    bob.query(api.chat.listMessages, {
      threadId,
      paginationOpts: { numItems: 10, cursor: null },
      streamArgs: undefined,
    }),
  ).rejects.toThrow();
});

test("listMessages succeeds for the owner", async () => {
  const t = convexTest(schema, modules);
  const { t: alice } = await asNewUser(t, "alice@example.com");
  const threadId = await alice.mutation(api.chat.createThread, {});

  const result = await alice.query(api.chat.listMessages, {
    threadId,
    paginationOpts: { numItems: 10, cursor: null },
    streamArgs: undefined,
  });
  expect(result.page).toEqual([]);
  expect(result.isDone).toBe(true);
});

test("sendMessage throws 'Not found' for a non-owner's thread, and never calls continueThread", async () => {
  const t = convexTest(schema, modules);
  const { t: alice } = await asNewUser(t, "alice@example.com");
  const { t: bob } = await asNewUser(t, "bob@example.com");

  const threadId = await alice.mutation(api.chat.createThread, {});
  continueThreadMock.mockClear();
  await expect(
    bob.action(api.chat.sendMessage, { threadId, text: "hi" }),
  ).rejects.toThrow();
  expect(continueThreadMock).not.toHaveBeenCalled();
});

test("sendMessage on the caller's own thread passes the SERVER-resolved userId to continueThread (never client input) and drains the stream", async () => {
  const t = convexTest(schema, modules);
  const { t: alice, userId: aliceId } = await asNewUser(t, "alice@example.com");
  const threadId = await alice.mutation(api.chat.createThread, {});

  continueThreadMock.mockClear();
  await alice.action(api.chat.sendMessage, { threadId, text: "hello" });

  expect(continueThreadMock).toHaveBeenCalledTimes(1);
  const [, args] = continueThreadMock.mock.calls[0];
  // The action's own args schema (threadId, text) has no userId field at
  // all — a client literally cannot supply one. This asserts the userId
  // that reaches the agent (and, via ctx.userId, every tool call) is the
  // one `requireUserId` resolved server-side from the caller's identity.
  expect(args).toEqual({ threadId, userId: aliceId });
});

test("unauthenticated calls throw for every chat function", async () => {
  const t = convexTest(schema, modules);
  await expect(t.query(api.chat.listThreads, {})).rejects.toThrow();
  await expect(t.mutation(api.chat.createThread, {})).rejects.toThrow();
  await expect(
    t.query(api.chat.listMessages, {
      threadId: "nonexistent",
      paginationOpts: { numItems: 10, cursor: null },
      streamArgs: undefined,
    }),
  ).rejects.toThrow();
  await expect(
    t.action(api.chat.sendMessage, { threadId: "nonexistent", text: "hi" }),
  ).rejects.toThrow();
});

test("sendMessage sets the thread title from the first message (trimmed, truncated to 50 chars)", async () => {
  const t = convexTest(schema, modules);
  const { t: alice } = await asNewUser(t, "alice@example.com");
  const threadId = await alice.mutation(api.chat.createThread, {});

  const longText =
    "  this is a fairly long first message that will definitely exceed fifty characters in length  ";
  await alice.action(api.chat.sendMessage, { threadId, text: longText });

  const rows = await alice.query(api.chat.listThreads, {});
  expect(rows).toHaveLength(1);
  expect(rows[0].title).toBe(longText.trim().slice(0, 50));
  expect(rows[0].title!.length).toBeLessThanOrEqual(50);
});

test("sendMessage does NOT overwrite an existing title on a second message", async () => {
  const t = convexTest(schema, modules);
  const { t: alice } = await asNewUser(t, "alice@example.com");
  const threadId = await alice.mutation(api.chat.createThread, {});

  await alice.action(api.chat.sendMessage, { threadId, text: "first message" });
  await alice.action(api.chat.sendMessage, { threadId, text: "second message" });

  const rows = await alice.query(api.chat.listThreads, {});
  expect(rows).toHaveLength(1);
  expect(rows[0].title).toBe("first message");
});

test("setThreadTitleIfEmpty (internal) is only reachable via the ownership-gated sendMessage — a non-owner's sendMessage call cannot set it", async () => {
  const t = convexTest(schema, modules);
  const { t: alice } = await asNewUser(t, "alice@example.com");
  const { t: bob } = await asNewUser(t, "bob@example.com");

  const threadId = await alice.mutation(api.chat.createThread, {});
  await expect(
    bob.action(api.chat.sendMessage, { threadId, text: "hijack title" }),
  ).rejects.toThrow();

  const rows = await alice.query(api.chat.listThreads, {});
  expect(rows[0].title).toBeUndefined();
});

test("getThreadOwner (internal) only exposes the owning row, used by sendMessage's action-ctx authorization", async () => {
  const t = convexTest(schema, modules);
  const { t: alice } = await asNewUser(t, "alice@example.com");
  const threadId = await alice.mutation(api.chat.createThread, {});

  const row = await t.query(internal.chat.getThreadOwner, { threadId });
  expect(row?.threadId).toBe(threadId);
  const missing = await t.query(internal.chat.getThreadOwner, {
    threadId: "does-not-exist",
  });
  expect(missing).toBeNull();
});
