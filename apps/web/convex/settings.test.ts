// Tests for convex/settings.ts — the per-user model-selection API. The
// security invariant under test: setModel only ever persists an id from
// models.shared.ts's MODEL_ALLOWLIST (validated BEFORE the write), and
// getSettings fails closed to DEFAULT_MODEL when nothing is saved yet.
import { convexTest } from "convex-test";
import { afterEach, expect, test, vi } from "vitest";
import schema from "./schema";
import { api } from "./_generated/api";
import { DEFAULT_MODEL, MODEL_ALLOWLIST, MODEL_META } from "./models.shared";

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

afterEach(() => {
  vi.unstubAllGlobals();
});

test("listModels maps a successful OpenRouter response into allowlist rows with live pricing", async () => {
  const t = convexTest(schema, modules);
  const alice = await asNewUser(t, "alice@example.com");

  const fetchMock = vi.fn(async () => ({
    ok: true,
    json: async () => ({
      data: [
        {
          id: "openai/gpt-4o-mini",
          pricing: { prompt: "0.00000015", completion: "0.0000006" },
        },
        // An entry OpenRouter returns that isn't in our allowlist — must be ignored.
        { id: "some/other-model", pricing: { prompt: "1", completion: "2" } },
      ],
    }),
  }));
  vi.stubGlobal("fetch", fetchMock);

  const rows = await alice.action(api.settings.listModels, {});

  expect(fetchMock).toHaveBeenCalledTimes(1);
  expect(rows).toHaveLength(MODEL_ALLOWLIST.length);
  for (const id of MODEL_ALLOWLIST) {
    const meta = MODEL_META[id as keyof typeof MODEL_META];
    const row = rows.find((r) => r.id === id);
    expect(row).toBeDefined();
    expect(row).toMatchObject({
      name: meta.name,
      toolRating: meta.toolRating,
      ragRating: meta.ragRating,
    });
  }

  const priced = rows.find((r) => r.id === "openai/gpt-4o-mini");
  expect(priced?.promptPrice).toBeCloseTo(0.15);
  expect(priced?.completionPrice).toBeCloseTo(0.6);

  // Only the id present in the mocked OpenRouter response gets live pricing;
  // every other allowlist entry fails soft to null prices.
  for (const id of MODEL_ALLOWLIST) {
    if (id === "openai/gpt-4o-mini") continue;
    const row = rows.find((r) => r.id === id);
    expect(row?.promptPrice).toBeNull();
    expect(row?.completionPrice).toBeNull();
  }
});

test("listModels fails soft to null prices for every allowlist entry when the fetch fails", async () => {
  const t = convexTest(schema, modules);
  const alice = await asNewUser(t, "alice@example.com");

  vi.stubGlobal(
    "fetch",
    vi.fn(async () => {
      throw new Error("network down");
    }),
  );

  const rows = await alice.action(api.settings.listModels, {});

  expect(rows).toHaveLength(MODEL_ALLOWLIST.length);
  for (const id of MODEL_ALLOWLIST) {
    const meta = MODEL_META[id as keyof typeof MODEL_META];
    const row = rows.find((r) => r.id === id);
    expect(row).toMatchObject({
      id,
      name: meta.name,
      toolRating: meta.toolRating,
      ragRating: meta.ragRating,
      promptPrice: null,
      completionPrice: null,
    });
  }
});

test("listModels throws for an unauthenticated caller", async () => {
  const t = convexTest(schema, modules);
  await expect(t.action(api.settings.listModels, {})).rejects.toThrow();
});
