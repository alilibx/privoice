// Pure TS — NO Convex imports. Safe to import from both the server
// (convex/settings.ts, convex/chat.ts) and the client (src/, Task 7's
// Settings UI). This is the single source of truth for which chat models a
// user may select: `sendMessage` validates against this allowlist
// server-side before ever passing a model id to the LLM provider (see
// SECURITY note in convex/settings.ts and convex/chat.ts) — the client can
// suggest a model id, but generation only ever uses one that round-tripped
// through this allowlist check.
export const DEFAULT_MODEL = "openai/gpt-4o-mini";

export const MODEL_META = {
  "openai/gpt-4o-mini": { name: "GPT-4o mini", toolRating: "Good", ragRating: "Good" },
  "google/gemini-2.5-flash": { name: "Gemini 2.5 Flash", toolRating: "Good", ragRating: "Strong" },
  "anthropic/claude-haiku-4.5": { name: "Claude Haiku 4.5", toolRating: "Strong", ragRating: "Strong" },
  "anthropic/claude-sonnet-5": { name: "Claude Sonnet 5", toolRating: "Best", ragRating: "Best" },
  "openai/gpt-5.4": { name: "GPT-5.4", toolRating: "Strong", ragRating: "Strong" },
  "openai/gpt-5.5": { name: "GPT-5.5", toolRating: "Best", ragRating: "Best" },
} as const satisfies Record<string, { name: string; toolRating: string; ragRating: string }>;

export const MODEL_ALLOWLIST: readonly string[] = Object.keys(MODEL_META);

export function isAllowedModel(id: string): boolean {
  return MODEL_ALLOWLIST.includes(id);
}
