// Tests for convex/settings.ts — the per-user model-selection API. The
// security invariant under test: setModel only ever persists an id from
// models.shared.ts's MODEL_ALLOWLIST (validated BEFORE the write), and
// getSettings fails closed to DEFAULT_MODEL when nothing is saved yet.
import { convexTest } from "convex-test";
import { expect, test } from "vitest";
import schema from "./schema";
import { api } from "./_generated/api";
import { DEFAULT_MODEL } from "./models.shared";

const modules = import.meta.glob("./**/*.ts");

async function asNewUser(t: ReturnType<typeof convexTest>, email: string) {
  const userId = await t.run(async (ctx) => ctx.db.insert("users", { email }));
  return t.withIdentity({ subject: `${userId}|session_${userId}` });
}

test("getSettings returns DEFAULT_MODEL when the caller has no saved settings", async () => {
  const t = convexTest(schema, modules);
  const alice = await asNewUser(t, "alice@example.com");
  const settings = await alice.query(api.settings.getSettings, {});
  expect(settings).toEqual({ modelId: DEFAULT_MODEL });
});

test("setModel persists an allowlisted id, reflected by a subsequent getSettings", async () => {
  const t = convexTest(schema, modules);
  const alice = await asNewUser(t, "alice@example.com");
  await alice.mutation(api.settings.setModel, {
    modelId: "anthropic/claude-sonnet-5",
  });
  const settings = await alice.query(api.settings.getSettings, {});
  expect(settings).toEqual({ modelId: "anthropic/claude-sonnet-5" });
});

test("setModel called twice upserts (patches) rather than duplicating the row", async () => {
  const t = convexTest(schema, modules);
  const alice = await asNewUser(t, "alice@example.com");
  await alice.mutation(api.settings.setModel, { modelId: "openai/gpt-5.4" });
  await alice.mutation(api.settings.setModel, {
    modelId: "google/gemini-2.5-flash",
  });
  const settings = await alice.query(api.settings.getSettings, {});
  expect(settings).toEqual({ modelId: "google/gemini-2.5-flash" });
});

test("setModel throws ConvexError for a non-allowlisted id, and does not persist it", async () => {
  const t = convexTest(schema, modules);
  const alice = await asNewUser(t, "alice@example.com");
  await expect(
    alice.mutation(api.settings.setModel, { modelId: "evil/model" }),
  ).rejects.toThrow();
  const settings = await alice.query(api.settings.getSettings, {});
  expect(settings).toEqual({ modelId: DEFAULT_MODEL });
});

test("getSettings and setModel are scoped per-user", async () => {
  const t = convexTest(schema, modules);
  const alice = await asNewUser(t, "alice@example.com");
  const bob = await asNewUser(t, "bob@example.com");
  await alice.mutation(api.settings.setModel, {
    modelId: "anthropic/claude-haiku-4.5",
  });
  expect(await bob.query(api.settings.getSettings, {})).toEqual({
    modelId: DEFAULT_MODEL,
  });
  expect(await alice.query(api.settings.getSettings, {})).toEqual({
    modelId: "anthropic/claude-haiku-4.5",
  });
});

test("unauthenticated calls throw for both getSettings and setModel", async () => {
  const t = convexTest(schema, modules);
  await expect(t.query(api.settings.getSettings, {})).rejects.toThrow();
  await expect(
    t.mutation(api.settings.setModel, { modelId: "openai/gpt-4o-mini" }),
  ).rejects.toThrow();
});
