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
    // The ids of documents/meetings attached to the message currently being
    // generated (already validated + stored by sendMessage's setPins call —
    // see chat.ts) so pinAndBoost can prioritize the attachment.
    const pinnedSourceIds = await ctx.runQuery(internal.chat.getPins, {
      userId: userId as Id<"users">,
    });
    const result = await retrieve(ctx, {
      userId,
      query,
      source,
      pinnedSourceIds,
    });
    return `${result.pack}${SOURCES_MARKER}${JSON.stringify(result.sources)}`;
  },
});

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(0)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}

export const listDocuments = createTool({
  description:
    "List ALL of the user's uploaded documents by name (with type and status). Use this when the user asks to list, count, or see their documents — not for content questions.",
  inputSchema: z.object({}),
  execute: async (ctx): Promise<string> => {
    const userId = requireCallerUserId(ctx);
    const docs: Array<{
      filename: string;
      kind: string;
      status: string;
      sizeBytes: number;
      createdAt: number;
    }> = await ctx.runQuery(internal.documents.listForUser, {
      userId: userId as Id<"users">,
    });
    if (docs.length === 0) return "The user has no uploaded documents.";
    const lines = docs.map(
      (d) =>
        `- ${d.filename} (${d.kind}, ${formatBytes(d.sizeBytes)}${d.status !== "ready" ? `, ${d.status}` : ""})`,
    );
    return `The user has ${docs.length} document${docs.length === 1 ? "" : "s"}:\n${lines.join("\n")}`;
  },
});

const READ_MAX_LINES = 200;
const READ_MAX_CHARS = 8192;

export const readDocument = createTool({
  description:
    "Read a specific range of lines from ONE known document or meeting by its sourceId, returned with line numbers. Read positionally — e.g. the first line (startLine 1, maxLines 1), an intro, or to expand around a grep match. Not for searching: use grep or searchKnowledge to find things first.",
  inputSchema: z.object({
    sourceId: z.string().describe("The sourceId of the document or meeting to read"),
    startLine: z.number().optional().describe("1-indexed line to start at (default 1)"),
    maxLines: z.number().optional().describe("How many lines to return (default 50, max 200)"),
  }),
  execute: async (ctx, { sourceId, startLine, maxLines }): Promise<string> => {
    const userId = requireCallerUserId(ctx);
    const text: string = await ctx.runQuery(internal.knowledge.linesFor, {
      userId: userId as Id<"users">,
      sourceId,
    });
    if (!text) return "No content found for that document.";
    const lines = text.split("\n");
    const start = Math.max(1, Math.floor(startLine ?? 1));
    const count = Math.min(READ_MAX_LINES, Math.max(1, Math.floor(maxLines ?? 50)));
    if (start > lines.length) return `Document has only ${lines.length} lines.`;
    const end = Math.min(lines.length, start - 1 + count);
    const width = String(end).length;
    const body = lines
      .slice(start - 1, end)
      .map((line, i) => `${String(start + i).padStart(width)}  ${line}`)
      .join("\n");
    let out = `lines ${start}–${end} of ${lines.length}:\n${body}`;
    if (out.length > READ_MAX_CHARS) {
      out = out.slice(0, READ_MAX_CHARS) + "\n… (truncated)";
    }
    return out;
  },
});

const CONTEXT_LINES = 2;
const MAX_WINDOWS = 40;
// Security hardening: cap the model-supplied regex pattern length BEFORE
// compiling it, to bound the cost of pathological patterns (ReDoS) —
// checked before `new RegExp` so an expensive-to-compile-or-run pattern
// never reaches the regex engine.
const MAX_PATTERN_LENGTH = 200;
const GREP_MAX_SOURCES = 200;
const GREP_MAX_CHARS = 8192;

// Scan one reconstructed source's text for regex matches, returning numbered,
// context-padded, merged blocks each headed by `title:firstLineNo`. Empty
// array when nothing matches. Shared by grep's scoped and corpus modes.
function grepSource(title: string, text: string, regex: RegExp): string[] {
  if (!text) return [];
  const lines = text.split("\n");
  const windows: Array<[number, number]> = [];
  for (let i = 0; i < lines.length; i++) {
    if (regex.test(lines[i])) {
      windows.push([Math.max(0, i - CONTEXT_LINES), Math.min(lines.length - 1, i + CONTEXT_LINES)]);
    }
  }
  if (windows.length === 0) return [];

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

  const width = String(lines.length).length;
  return merged.map(([start, end]) => {
    const numbered = lines
      .slice(start, end + 1)
      .map((line, k) => `${String(start + 1 + k).padStart(width)}  ${line}`)
      .join("\n");
    return `${title}:${start + 1}\n${numbered}`;
  });
}

export const grep = createTool({
  description:
    "Search the user's documents and meetings for an exact value or phrase by regular expression. Omit sourceId to search across ALL sources; pass a sourceId to search within one. Returns matching lines with line numbers under a `title:line` header — hand a match's line to readDocument to read the surrounding section.",
  inputSchema: z.object({
    pattern: z.string().describe("A regular expression, e.g. an amount, date, clause number, or phrase"),
    sourceId: z.string().optional().describe("Optional: restrict the search to a single document or meeting by its sourceId"),
  }),
  execute: async (ctx, { pattern, sourceId }): Promise<string> => {
    const userId = requireCallerUserId(ctx);
    if (pattern.length > MAX_PATTERN_LENGTH) return "Search pattern too long.";
    let regex: RegExp;
    try {
      regex = new RegExp(pattern, "i");
    } catch {
      return "Invalid search pattern.";
    }

    // Assemble the sources to scan: one (scoped) or all (corpus).
    let sources: Array<{ sourceId: string; title: string; text: string }>;
    let sourcesCapped = false;
    if (sourceId) {
      const text: string = await ctx.runQuery(internal.knowledge.linesFor, {
        userId: userId as Id<"users">,
        sourceId,
      });
      // linesFor returns only text; label the scoped hit by its sourceId
      // (the model already knows which doc it asked for).
      sources = [{ sourceId, title: sourceId, text }];
    } else {
      const all: Array<{ sourceId: string; title: string; source: string; text: string }> =
        await ctx.runQuery(internal.knowledge.corpusForUser, {
          userId: userId as Id<"users">,
        });
      sourcesCapped = all.length > GREP_MAX_SOURCES;
      sources = all.slice(0, GREP_MAX_SOURCES);
    }

    const blocks: string[] = [];
    for (const src of sources) {
      if (blocks.length >= MAX_WINDOWS) break;
      for (const block of grepSource(src.title, src.text, regex)) {
        blocks.push(block);
        if (blocks.length >= MAX_WINDOWS) break;
      }
    }

    if (blocks.length === 0) return "No matches found.";
    let out = blocks.join("\n---\n");
    if (out.length > GREP_MAX_CHARS) out = out.slice(0, GREP_MAX_CHARS) + "\n… (truncated)";
    if (sourcesCapped) out += `\n\n(Searched the first ${GREP_MAX_SOURCES} sources; more exist.)`;
    return out;
  },
});
