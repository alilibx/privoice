import { v, ConvexError } from "convex/values";
import { query, mutation, action } from "./_generated/server";
import { getAuthUserId } from "@convex-dev/auth/server";
import {
  DEFAULT_MODEL,
  MODEL_ALLOWLIST,
  MODEL_META,
  isAllowedModel,
} from "./models.shared";

// SECURITY: this is the only path that writes userSettings.modelId, and it
// validates against MODEL_ALLOWLIST (models.shared.ts) BEFORE the write —
// never after. sendMessage (chat.ts) re-validates on read (fail-closed to
// DEFAULT_MODEL) so a bad value can never reach generation even if it somehow
// ended up in the table by another path.
export const getSettings = query({
  args: {},
  handler: async (ctx) => {
    const userId = await getAuthUserId(ctx);
    if (userId === null) throw new ConvexError("Not authenticated");
    const row = await ctx.db
      .query("userSettings")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .unique();
    return { modelId: row?.modelId ?? DEFAULT_MODEL };
  },
});

export const setModel = mutation({
  args: { modelId: v.string() },
  handler: async (ctx, { modelId }) => {
    const userId = await getAuthUserId(ctx);
    if (userId === null) throw new ConvexError("Not authenticated");
    if (!isAllowedModel(modelId)) {
      throw new ConvexError("Unsupported model");
    }
    const row = await ctx.db
      .query("userSettings")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .unique();
    if (row === null) {
      await ctx.db.insert("userSettings", {
        userId,
        modelId,
        updatedAt: Date.now(),
      });
    } else {
      await ctx.db.patch(row._id, { modelId, updatedAt: Date.now() });
    }
  },
});

// Action (not query) because it calls out to the OpenRouter models endpoint
// for live pricing. Fails soft: on any fetch/parse error it still returns
// the full curated allowlist, just with null prices, so the Settings UI (Task
// 7) always has a model list to render. OPENROUTER_API_KEY is read from
// process.env only, used solely as an outbound bearer token here — never
// included in the returned array or in any thrown/logged error message.
export const listModels = action({
  args: {},
  handler: async (ctx) => {
    const userId = await getAuthUserId(ctx);
    if (userId === null) throw new ConvexError("Not authenticated");

    const prices = new Map<string, { prompt: number | null; completion: number | null }>();
    try {
      const res = await fetch("https://openrouter.ai/api/v1/models", {
        headers: { Authorization: `Bearer ${process.env.OPENROUTER_API_KEY}` },
      });
      if (res.ok) {
        const body = (await res.json()) as {
          data?: Array<{
            id: string;
            pricing?: { prompt?: string | number; completion?: string | number };
          }>;
        };
        for (const entry of body.data ?? []) {
          const promptRaw = entry.pricing?.prompt;
          const completionRaw = entry.pricing?.completion;
          const prompt = promptRaw != null ? Number(promptRaw) * 1e6 : null;
          const completion =
            completionRaw != null ? Number(completionRaw) * 1e6 : null;
          prices.set(entry.id, {
            prompt: Number.isFinite(prompt) ? prompt : null,
            completion: Number.isFinite(completion) ? completion : null,
          });
        }
      }
    } catch {
      // fail-soft: `prices` stays empty, every entry below gets null prices.
    }

    return MODEL_ALLOWLIST.map((id) => {
      const meta = MODEL_META[id as keyof typeof MODEL_META];
      const price = prices.get(id);
      return {
        id,
        name: meta.name,
        toolRating: meta.toolRating,
        ragRating: meta.ragRating,
        promptPrice: price?.prompt ?? null,
        completionPrice: price?.completion ?? null,
      };
    });
  },
});
