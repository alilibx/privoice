import { convexTest } from "convex-test";
import { expect, test } from "vitest";
import schema from "./schema";
import { api, internal } from "./_generated/api";

// convex-test loads all backend modules from this glob.
const modules = import.meta.glob("./**/*.ts");

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

// searchByUser is internal-only (called by the chat agent's searchMeetings
// tool with a server-resolved userId — see tools.ts), but its case-
// insensitive substring matching and by_user scoping deserve their own
// direct coverage, independent of the tool's ctx-resolution logic.
test("searchByUser matches title/notes case-insensitively, scoped to the given userId", async () => {
  const t = convexTest(schema, modules);
  const alice = await asNewUser(t, "alice@example.com");
  const bob = await asNewUser(t, "bob@example.com");
  const aliceId = await alice.mutation(api.meetings.create, {
    title: "Roadmap Review",
    notes: "Q3 planning notes",
  });
  await bob.mutation(api.meetings.create, { title: "roadmap sync" });

  const aliceRow = await t.run((ctx) => ctx.db.get(aliceId));
  const results = await t.query(internal.meetings.searchByUser, {
    userId: aliceRow!.userId,
    query: "ROADMAP",
  });
  expect(results).toHaveLength(1);
  expect(results[0].title).toBe("Roadmap Review");

  const byNotes = await t.query(internal.meetings.searchByUser, {
    userId: aliceRow!.userId,
    query: "q3 planning",
  });
  expect(byNotes).toHaveLength(1);

  const noMatch = await t.query(internal.meetings.searchByUser, {
    userId: aliceRow!.userId,
    query: "nonexistent",
  });
  expect(noMatch).toHaveLength(0);
});
