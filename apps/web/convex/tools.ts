import { createTool, type ToolCtx } from "@convex-dev/agent";
import { z } from "zod";
import { internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import { retrieve } from "./retrieval/retrieve";

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

// Marker the client (see ToolTrace/Chat) splits on to separate the prose
// "pack" the model reads from the structured sources list it renders as
// numbered citations. Keeping it out-of-band like this means the model
// never has to reproduce or paraphrase the sources JSON itself — it just
// cites `[n]` and the UI resolves `n` against this block.
const SOURCES_MARKER = "\n\n<<<SOURCES>>>\n";

export const searchKnowledge = createTool({
  description:
    "Search the user's documents and meetings for relevant passages to answer the question.",
  inputSchema: z.object({
    query: z.string().describe("What to look for"),
    source: z.enum(["document", "meeting"]).optional().describe(
      "Optionally restrict the search to only documents or only meetings",
    ),
  }),
  execute: async (ctx, { query, source }): Promise<string> => {
    const userId = requireCallerUserId(ctx);
    // NOTE: `internal.chat.getPins` (Task 9) will supply the caller's pinned
    // sources here; until then, no pins are applied.
    const result = await retrieve(ctx, {
      userId,
      query,
      source,
      pinnedSourceIds: [],
    });
    return `${result.pack}${SOURCES_MARKER}${JSON.stringify(result.sources)}`;
  },
});

const CONTEXT_LINES = 2;
const MAX_WINDOWS = 40;

export const pinpoint = createTool({
  description:
    "Find exact values (dates, amounts, clause numbers, names) within a single known source by regex pattern, returning the matching lines with surrounding context.",
  inputSchema: z.object({
    sourceId: z.string().describe("The sourceId of the document or meeting to search within"),
    pattern: z.string().describe("A regular expression to search for, e.g. an amount or date pattern"),
  }),
  execute: async (ctx, { sourceId, pattern }): Promise<string> => {
    const userId = requireCallerUserId(ctx);
    const text: string = await ctx.runQuery(internal.knowledge.linesFor, {
      userId: userId as Id<"users">,
      sourceId,
    });

    let regex: RegExp;
    try {
      regex = new RegExp(pattern, "i");
    } catch {
      return "Invalid search pattern.";
    }

    if (!text) return "No matches found.";
    const lines = text.split("\n");

    const windows: Array<[number, number]> = [];
    for (let i = 0; i < lines.length; i++) {
      if (regex.test(lines[i])) {
        windows.push([Math.max(0, i - CONTEXT_LINES), Math.min(lines.length - 1, i + CONTEXT_LINES)]);
      }
    }
    if (windows.length === 0) return "No matches found.";

    // Merge overlapping/adjacent windows so shared context isn't duplicated.
    windows.sort((a, b) => a[0] - b[0]);
    const merged: Array<[number, number]> = [];
    for (const [start, end] of windows) {
      const last = merged[merged.length - 1];
      if (last && start <= last[1] + 1) {
        last[1] = Math.max(last[1], end);
      } else {
        merged.push([start, end]);
      }
    }

    const capped = merged.slice(0, MAX_WINDOWS);
    const blocks = capped.map(([start, end]) => lines.slice(start, end + 1).join("\n"));
    return blocks.join("\n---\n");
  },
});
