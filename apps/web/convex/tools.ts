import { createTool, type ToolCtx } from "@convex-dev/agent";
import { z } from "zod";
import { internal } from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import { ragSearch } from "./rag";

// SECURITY: these tools are only ever invoked by the agent runtime while
// generating a response (see agent.ts + chat.ts's `sendMessage`), which
// injects `ctx.userId` from the SERVER-resolved caller passed to
// `chatAgent.continueThread(ctx, { threadId, userId })` — never from a
// client- or model-supplied argument. The tools' own input schemas
// deliberately have no `userId` field, so the model has no way to ask for
// another user's data even if it tried. If `ctx.userId` is ever missing
// (e.g. the tool were invoked outside an authenticated per-user generation),
// we fail closed rather than guessing or defaulting to "no scope".
function requireCallerUserId(ctx: ToolCtx): string {
  if (!ctx.userId) {
    throw new Error("Tool called without an authenticated user in scope");
  }
  return ctx.userId;
}

export const searchDocuments = createTool({
  description: "Search the user's uploaded documents for relevant passages.",
  inputSchema: z.object({ query: z.string().describe("What to look for") }),
  execute: async (ctx, { query }): Promise<string> => {
    const userId = requireCallerUserId(ctx);
    const { text } = await ragSearch(ctx, { userId, query });
    return text || "No relevant documents found.";
  },
});

export const searchMeetings = createTool({
  description: "Search the user's meetings by title and notes.",
  inputSchema: z.object({ query: z.string() }),
  execute: async (ctx, { query }): Promise<string> => {
    const userId = requireCallerUserId(ctx);
    const rows: Doc<"meetings">[] = await ctx.runQuery(
      internal.meetings.searchByUser,
      {
        userId: userId as Id<"users">,
        query,
      },
    );
    return (
      rows.map((m) => `- ${m.title}: ${m.notes ?? ""}`).join("\n") ||
      "No matching meetings."
    );
  },
});
