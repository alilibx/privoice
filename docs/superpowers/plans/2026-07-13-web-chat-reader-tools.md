# C7 — Web chat document reader tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the chat agent a positional read tool (`readDocument`) and a corpus-wide `grep` (replacing `pinpoint`), so it can read documents by position and locate exact values across all sources.

**Architecture:** New/generalized `createTool` tools in `apps/web/convex/tools.ts`, backed by new grouped-scan queries in `apps/web/convex/knowledge.ts`. `readDocument` reuses the existing `linesFor` query; `grep` adds a corpus mode via a new `corpusForUser` query; `listDocuments` gains a `sourceId` handle + `lineCount`. All security invariants (fail-closed `ctx.userId`, `internalQuery`-only backends, ReDoS pattern cap) are preserved.

**Tech Stack:** Convex (TypeScript), `@convex-dev/agent` `createTool`, `zod` schemas, `vitest` + `convex-test`.

## Global Constraints

- **Security invariant:** every tool calls `requireCallerUserId(ctx)` and fails closed; no tool input schema has a `userId` field; all backing queries are `internalQuery` scoped to the caller's `userId` on an index. (verbatim from spec §Security)
- **ReDoS bound:** reject `pattern.length > MAX_PATTERN_LENGTH` (200) **before** `new RegExp`. (verbatim from spec §2)
- **Line semantics:** "lines" = `reconstructedText.split("\n")`, 1-indexed, where reconstructed text is the source's `knowledgeChunks` sorted by `chunkIndex` and joined with `\n` — identical to `linesFor`. (verbatim from spec §Terminology)
- **Caps:** `readDocument` — `MAX_LINES = 200`, `MAX_CHARS = 8192`. `grep` — `MAX_PATTERN_LENGTH = 200`, `MAX_WINDOWS = 40` (total across result), `GREP_MAX_SOURCES = 200`, char cap 8192.
- **Both `readDocument` and `grep` operate on any `sourceId`** (document or meeting). `listDocuments` stays documents-only.
- **Test runner:** `cd apps/web && npx vitest run <file>` for a single suite; `melos run analyze && melos run test` for the final gate.
- **Commits:** conventional commits; this plan's branch `feat/web-chat-reader-tools` already exists (off `main`).

---

### Task 1: Backend queries — grouped source reconstruction (`corpusForUser`, `lineCountsForUser`)

**Files:**
- Modify: `apps/web/convex/knowledge.ts` (add helper + queries after `linesFor`, ~line 98)
- Test: `apps/web/convex/knowledge.test.ts` (append)

**Interfaces:**
- Consumes: existing `knowledgeChunks` table + `by_user` index; `QueryCtx`, `Id` (already imported in knowledge.ts).
- Produces:
  - `reconstructedSourcesForUser(ctx: QueryCtx, userId: Id<"users">): Promise<Array<{ sourceId: string; title: string; source: string; text: string }>>` — plain helper.
  - `corpusForUser` internalQuery: `{ userId: v.id("users") }` → same array. (used by `grep` via `ctx.runQuery`)
  - `lineCountsForUser(ctx: QueryCtx, userId: Id<"users">): Promise<Record<string, number>>` — plain helper (used directly by `documents.listForUser`).

- [ ] **Step 1: Write the failing tests**

Append to `apps/web/convex/knowledge.test.ts`:

```ts
import {
  bm25Search,
  reconstructedSourcesForUser,
  lineCountsForUser,
} from "./knowledge";

test("reconstructedSourcesForUser groups a user's chunks per source, ordered by chunkIndex", async () => {
  const t = convexTest(schema);
  const userId = await t.run(async (ctx) => ctx.db.insert("users", {} as any));
  await t.mutation(internal.knowledge.insertChunks, {
    userId, entryId: "e1", source: "document", sourceId: "d1",
    title: "Doc One", chunks: ["alpha", "beta"],
  });
  await t.mutation(internal.knowledge.insertChunks, {
    userId, entryId: "e2", source: "meeting", sourceId: "m1",
    title: "Standup", chunks: ["gamma"],
  });

  const sources = await t.run((ctx) => reconstructedSourcesForUser(ctx, userId));
  const byId = Object.fromEntries(sources.map((s) => [s.sourceId, s]));
  expect(byId["d1"]).toMatchObject({ title: "Doc One", source: "document", text: "alpha\nbeta" });
  expect(byId["m1"]).toMatchObject({ title: "Standup", source: "meeting", text: "gamma" });
});

test("corpusForUser is scoped to the caller — a stranger sees none of it", async () => {
  const t = convexTest(schema);
  const userId = await t.run(async (ctx) => ctx.db.insert("users", {} as any));
  const other = await t.run(async (ctx) => ctx.db.insert("users", {} as any));
  await t.mutation(internal.knowledge.insertChunks, {
    userId, entryId: "e1", source: "document", sourceId: "d1",
    title: "Doc One", chunks: ["alpha", "beta"],
  });

  const mine = await t.query(internal.knowledge.corpusForUser, { userId });
  expect(mine.map((s) => s.sourceId)).toEqual(["d1"]);
  const theirs = await t.query(internal.knowledge.corpusForUser, { userId: other });
  expect(theirs).toEqual([]);
});

test("lineCountsForUser counts reconstructed lines per source", async () => {
  const t = convexTest(schema);
  const userId = await t.run(async (ctx) => ctx.db.insert("users", {} as any));
  await t.mutation(internal.knowledge.insertChunks, {
    userId, entryId: "e1", source: "document", sourceId: "d1",
    title: "Doc One", chunks: ["one\ntwo", "three"], // joins to "one\ntwo\nthree" → 3 lines
  });

  const counts = await t.run((ctx) => lineCountsForUser(ctx, userId));
  expect(counts["d1"]).toBe(3);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/web && npx vitest run convex/knowledge.test.ts`
Expected: FAIL — `reconstructedSourcesForUser`/`lineCountsForUser` are not exported; `corpusForUser` not on `internal.knowledge`.

- [ ] **Step 3: Implement the helper + queries**

In `apps/web/convex/knowledge.ts`, insert after the `linesFor` query (after line 98):

```ts
// Group all of a user's knowledgeChunks by sourceId and reconstruct each
// source's full text (chunks sorted by chunkIndex, joined with "\n") — the
// same reconstruction linesFor does for one source, done for the whole
// corpus in a single by_user scan. Backs corpus-mode grep and line counts.
export async function reconstructedSourcesForUser(
  ctx: QueryCtx,
  userId: Id<"users">,
): Promise<Array<{ sourceId: string; title: string; source: string; text: string }>> {
  const rows = await ctx.db
    .query("knowledgeChunks")
    .withIndex("by_user", (q) => q.eq("userId", userId))
    .collect();
  const groups = new Map<
    string,
    { title: string; source: string; chunks: Array<{ i: number; t: string }> }
  >();
  for (const r of rows) {
    let g = groups.get(r.sourceId);
    if (!g) {
      g = { title: r.title, source: r.source, chunks: [] };
      groups.set(r.sourceId, g);
    }
    g.chunks.push({ i: r.chunkIndex, t: r.chunkText });
  }
  return [...groups.entries()].map(([sourceId, g]) => ({
    sourceId,
    title: g.title,
    source: g.source,
    text: g.chunks.sort((a, b) => a.i - b.i).map((c) => c.t).join("\n"),
  }));
}

export const corpusForUser = internalQuery({
  args: { userId: v.id("users") },
  handler: (ctx, { userId }) => reconstructedSourcesForUser(ctx, userId),
});

export async function lineCountsForUser(
  ctx: QueryCtx,
  userId: Id<"users">,
): Promise<Record<string, number>> {
  const sources = await reconstructedSourcesForUser(ctx, userId);
  const counts: Record<string, number> = {};
  for (const s of sources) {
    counts[s.sourceId] = s.text.length === 0 ? 0 : s.text.split("\n").length;
  }
  return counts;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/web && npx vitest run convex/knowledge.test.ts`
Expected: PASS (all suites, including the 3 new ones).

- [ ] **Step 5: Commit**

```bash
git add apps/web/convex/knowledge.ts apps/web/convex/knowledge.test.ts
git commit -m "feat(web): corpusForUser + lineCountsForUser knowledge queries"
```

---

### Task 2: `readDocument` tool — positional, line-numbered read

**Files:**
- Modify: `apps/web/convex/tools.ts` (add tool; add constants)
- Modify: `apps/web/convex/agent.ts` (register tool + prompt clause)
- Test: `apps/web/convex/tools.test.ts` (append)

**Interfaces:**
- Consumes: existing `internal.knowledge.linesFor`; `requireCallerUserId`, `Id` (already in tools.ts).
- Produces: `readDocument` tool exported from `tools.ts`.

- [ ] **Step 1: Write the failing tests**

Append to `apps/web/convex/tools.test.ts`:

```ts
test("readDocument returns just line 1, numbered, with a range header (first-line case)", async () => {
  const runQuery = vi.fn(async () => "first line\nsecond line\nthird line");
  const { readDocument } = await import("./tools");
  const tool = withCtx(readDocument, { userId: "alice_id", runQuery });
  const result = await tool.execute!(
    { sourceId: "d1", startLine: 1, maxLines: 1 },
    { toolCallId: "r1", messages: [] } as any,
  );
  const [, args] = runQuery.mock.calls[0];
  expect(args).toEqual({ userId: "alice_id", sourceId: "d1" });
  expect(result).toContain("lines 1–1 of 3:");
  expect(result).toContain("1  first line");
  expect(result).not.toContain("second line");
});

test("readDocument returns the requested window with correct numbering", async () => {
  const runQuery = vi.fn(async () => "a\nb\nc\nd\ne");
  const { readDocument } = await import("./tools");
  const tool = withCtx(readDocument, { userId: "alice_id", runQuery });
  const result = await tool.execute!(
    { sourceId: "d1", startLine: 2, maxLines: 2 },
    { toolCallId: "r2", messages: [] } as any,
  );
  expect(result).toContain("2  b");
  expect(result).toContain("3  c");
  expect(result).not.toContain("4  d");
});

test("readDocument clamps maxLines above the ceiling and coerces startLine below 1", async () => {
  const runQuery = vi.fn(async () => Array.from({ length: 500 }, (_, i) => `L${i + 1}`).join("\n"));
  const { readDocument } = await import("./tools");
  const tool = withCtx(readDocument, { userId: "alice_id", runQuery });
  const result = await tool.execute!(
    { sourceId: "d1", startLine: 0, maxLines: 9999 },
    { toolCallId: "r3", messages: [] } as any,
  );
  expect(result).toContain("lines 1–200 of 500:");
  expect(result).toContain("1  L1");
  expect(result).toContain("200  L200");
  expect(result).not.toContain("201  L201");
});

test("readDocument reports when startLine is past the end", async () => {
  const runQuery = vi.fn(async () => "only\ntwo");
  const { readDocument } = await import("./tools");
  const tool = withCtx(readDocument, { userId: "alice_id", runQuery });
  const result = await tool.execute!(
    { sourceId: "d1", startLine: 5 },
    { toolCallId: "r4", messages: [] } as any,
  );
  expect(result).toBe("Document has only 2 lines.");
});

test("readDocument truncates output past the char cap", async () => {
  const giant = "x".repeat(20000);
  const runQuery = vi.fn(async () => giant);
  const { readDocument } = await import("./tools");
  const tool = withCtx(readDocument, { userId: "alice_id", runQuery });
  const result = await tool.execute!(
    { sourceId: "d1" },
    { toolCallId: "r5", messages: [] } as any,
  );
  expect(result.length).toBeLessThanOrEqual(8192 + "\n… (truncated)".length);
  expect(result.endsWith("… (truncated)")).toBe(true);
});

test("readDocument returns a friendly message for an empty/missing document", async () => {
  const runQuery = vi.fn(async () => "");
  const { readDocument } = await import("./tools");
  const tool = withCtx(readDocument, { userId: "alice_id", runQuery });
  const result = await tool.execute!(
    { sourceId: "nope" },
    { toolCallId: "r6", messages: [] } as any,
  );
  expect(result).toBe("No content found for that document.");
});

test("readDocument fails closed without a caller in scope", async () => {
  const runQuery = vi.fn();
  const { readDocument } = await import("./tools");
  const tool = withCtx(readDocument, { runQuery });
  await expect(
    tool.execute!({ sourceId: "d1" }, { toolCallId: "r7", messages: [] } as any),
  ).rejects.toThrow(/authenticated user/i);
  expect(runQuery).not.toHaveBeenCalled();
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/web && npx vitest run convex/tools.test.ts`
Expected: FAIL — `readDocument` is not exported from `./tools`.

- [ ] **Step 3: Implement the tool**

In `apps/web/convex/tools.ts`, add near the other constants (after `formatBytes`, before `listDocuments` is fine):

```ts
const READ_MAX_LINES = 200;
const READ_MAX_CHARS = 8192;
```

Then add the tool (e.g. after `listDocuments`):

```ts
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
```

> Note: the header uses `lines X–Y of N:` (no filename) — `linesFor` returns only text, and the model already supplied `sourceId`, so no extra round-trip is spent to fetch the filename. This is an intentional, minor simplification of the spec's illustrative header.

- [ ] **Step 4: Register in the agent**

In `apps/web/convex/agent.ts`:
- Change line 4 import to include `readDocument`:
  ```ts
  import { searchKnowledge, pinpoint, listDocuments, readDocument } from "./tools";
  ```
- Change the `tools:` object (line 18):
  ```ts
  tools: { searchKnowledge, pinpoint, listDocuments, readDocument },
  ```
- Append to the instructions string (end of the second string, before the closing quote): 
  ```
  " Use readDocument to read specific lines of a known source by its sourceId (e.g. the first line = startLine 1, maxLines 1)."
  ```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd apps/web && npx vitest run convex/tools.test.ts`
Expected: PASS (all suites, including the 7 new `readDocument` tests).

- [ ] **Step 6: Commit**

```bash
git add apps/web/convex/tools.ts apps/web/convex/tools.test.ts apps/web/convex/agent.ts
git commit -m "feat(web): readDocument tool — positional line-numbered read"
```

---

### Task 3: `pinpoint` → `grep` — corpus-wide regex with coordinates

**Files:**
- Modify: `apps/web/convex/tools.ts` (replace `pinpoint` with `grep`; add `grepSource` helper + constants)
- Modify: `apps/web/convex/agent.ts` (swap `pinpoint`→`grep` in import/registration/prompt)
- Test: `apps/web/convex/tools.test.ts` (replace the `pinpoint` tests with `grep` tests)

**Interfaces:**
- Consumes: `internal.knowledge.linesFor` (scoped mode), `internal.knowledge.corpusForUser` (corpus mode, from Task 1); `requireCallerUserId`, `Id`.
- Produces: `grep` tool exported from `tools.ts`. `pinpoint` is removed.

- [ ] **Step 1: Replace the pinpoint tests with grep tests**

In `apps/web/convex/tools.test.ts`:
- Change the top import (line 16) from `import { searchKnowledge, pinpoint } from "./tools";` to:
  ```ts
  import { searchKnowledge, grep } from "./tools";
  ```
- Delete the six `pinpoint …` tests (the `test("pinpoint …")` blocks).
- Add these `grep` tests in their place:

```ts
test("grep (scoped) returns matched line + context, numbered, scoped to ctx.userId", async () => {
  const runQuery = vi.fn(
    async (_ref: unknown, _args: { userId: string; sourceId: string }) =>
      "line one\nline two\nDate: 2024-05-01\nline four\nline five",
  );
  const tool = withCtx(grep, { userId: "bob_id", runQuery });
  const result = await tool.execute!(
    { pattern: "Date:", sourceId: "d1" },
    { toolCallId: "g1", messages: [] } as any,
  );
  const [, args] = runQuery.mock.calls[0];
  expect(args).toEqual({ userId: "bob_id", sourceId: "d1" });
  expect(result).toContain("Date: 2024-05-01");
  expect(result).toContain("3  Date: 2024-05-01"); // line number present
  expect(result).toContain("d1:"); // coordinate header
});

test("grep (corpus) searches all sources and labels each hit with title:line", async () => {
  const runQuery = vi.fn(async (_ref: unknown, _args: { userId: string }) => [
    { sourceId: "d1", title: "Contract A", source: "document", text: "foo\nindemnity clause\nbar" },
    { sourceId: "d2", title: "Contract B", source: "document", text: "nothing here" },
    { sourceId: "d3", title: "Contract C", source: "document", text: "more indemnity talk" },
  ]);
  const tool = withCtx(grep, { userId: "bob_id", runQuery });
  const result = await tool.execute!(
    { pattern: "indemnity" },
    { toolCallId: "g2", messages: [] } as any,
  );
  const [, args] = runQuery.mock.calls[0];
  expect(args).toEqual({ userId: "bob_id" });
  expect(result).toContain("Contract A:");
  expect(result).toContain("indemnity clause");
  expect(result).toContain("Contract C:");
  expect(result).not.toContain("Contract B:"); // no match there
});

test("grep returns a friendly message when nothing matches", async () => {
  const runQuery = vi.fn(async () => [
    { sourceId: "d1", title: "Doc", source: "document", text: "alpha\nbeta" },
  ]);
  const tool = withCtx(grep, { userId: "bob_id", runQuery });
  const result = await tool.execute!(
    { pattern: "nomatch-xyz" },
    { toolCallId: "g3", messages: [] } as any,
  );
  expect(result).toBe("No matches found.");
});

test("grep returns a friendly message for an invalid regex", async () => {
  const runQuery = vi.fn(async () => [
    { sourceId: "d1", title: "Doc", source: "document", text: "alpha" },
  ]);
  const tool = withCtx(grep, { userId: "bob_id", runQuery });
  const result = await tool.execute!(
    { pattern: "(unterminated" },
    { toolCallId: "g4", messages: [] } as any,
  );
  expect(result).toBe("Invalid search pattern.");
});

test("grep rejects an over-long pattern before compiling or querying (ReDoS hardening)", async () => {
  const runQuery = vi.fn();
  const tool = withCtx(grep, { userId: "bob_id", runQuery });
  const result = await tool.execute!(
    { pattern: "a".repeat(201) },
    { toolCallId: "g5", messages: [] } as any,
  );
  expect(result).toBe("Search pattern too long.");
  expect(runQuery).not.toHaveBeenCalled();
});

test("grep fails closed when ctx carries no userId", async () => {
  const runQuery = vi.fn();
  const tool = withCtx(grep, { runQuery });
  await expect(
    tool.execute!({ pattern: "x" }, { toolCallId: "g6", messages: [] } as any),
  ).rejects.toThrow(/authenticated user/i);
  expect(runQuery).not.toHaveBeenCalled();
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/web && npx vitest run convex/tools.test.ts`
Expected: FAIL — `grep` is not exported from `./tools`.

- [ ] **Step 3: Replace `pinpoint` with `grep` in tools.ts**

In `apps/web/convex/tools.ts`:
- Keep the existing constants `CONTEXT_LINES = 2`, `MAX_WINDOWS = 40`, `MAX_PATTERN_LENGTH = 200`. Add:
  ```ts
  const GREP_MAX_SOURCES = 200;
  const GREP_MAX_CHARS = 8192;
  ```
- Delete the entire `export const pinpoint = createTool({ … });` block (lines ~95–146).
- Add the shared scanner helper + the `grep` tool in its place:

```ts
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
  windows.sort((a, b) => a[0] - b[0]);
  const merged: Array<[number, number]> = [];
  for (const [start, end] of windows) {
    const last = merged[merged.length - 1];
    if (last && start <= last[1] + 1) last[1] = Math.max(last[1], end);
    else merged.push([start, end]);
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
```

- [ ] **Step 4: Swap the agent registration + prompt**

In `apps/web/convex/agent.ts`:
- Line 4 import: replace `pinpoint` with `grep`:
  ```ts
  import { searchKnowledge, grep, listDocuments, readDocument } from "./tools";
  ```
- `tools:` object:
  ```ts
  tools: { searchKnowledge, grep, listDocuments, readDocument },
  ```
- In the instructions string, replace every mention of `pinpoint` with `grep` and update its description. Specifically:
  - First string: `"…use the searchKnowledge / pinpoint tools…"` → `"…use the searchKnowledge / grep / readDocument tools…"`.
  - Second string: `"…use pinpoint to find exact values (dates, amounts, clause numbers) within a known source."` → `"…use grep to find exact values (dates, amounts, clause numbers, phrases) across all sources or within one; a grep hit is a title:line coordinate you can expand with readDocument."`

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd apps/web && npx vitest run convex/tools.test.ts`
Expected: PASS (searchKnowledge, listDocuments, readDocument, and the 6 new grep tests; no pinpoint references remain).

- [ ] **Step 6: Commit**

```bash
git add apps/web/convex/tools.ts apps/web/convex/tools.test.ts apps/web/convex/agent.ts
git commit -m "feat(web): generalize pinpoint into corpus-wide grep with line coordinates"
```

---

### Task 4: `listDocuments` — expose `sourceId` handle + `lineCount`

**Files:**
- Modify: `apps/web/convex/documents.ts` (`listForUser` returns `sourceId` + `lineCount`)
- Modify: `apps/web/convex/tools.ts` (`listDocuments` renders the handle + line count)
- Modify: `apps/web/convex/agent.ts` (prompt: use ids only as tool args)
- Test: `apps/web/convex/tools.test.ts` (update the `listDocuments` test); `apps/web/convex/documents.test.ts` (assert new fields)

**Interfaces:**
- Consumes: `lineCountsForUser` from `./knowledge` (Task 1).
- Produces: `listForUser` items now `{ sourceId, filename, kind, status, sizeBytes, lineCount, createdAt }`.

- [ ] **Step 1: Update the failing tests**

In `apps/web/convex/tools.test.ts`, replace the existing `listDocuments scopes to ctx.userId and formats the inventory` test's mock + assertions so the mock returns the new shape and the output includes the handle + line count:

```ts
test("listDocuments scopes to ctx.userId and formats the inventory with id handle + line count", async () => {
  const runQuery = vi.fn(async (_ref: unknown, _args: { userId: string }) => [
    { sourceId: "doc_a", filename: "a.pdf", kind: "pdf", status: "ready", sizeBytes: 2048, lineCount: 12, createdAt: 1 },
    { sourceId: "doc_b", filename: "b.txt", kind: "txt", status: "parsing", sizeBytes: 10, lineCount: 0, createdAt: 2 },
  ]);
  const { listDocuments } = await import("./tools");
  const tool = withCtx(listDocuments, { userId: "alice_id", runQuery });
  const result = await tool.execute!({}, { toolCallId: "t1", messages: [] } as any);

  const [, args] = runQuery.mock.calls[0];
  expect(args).toEqual({ userId: "alice_id" });
  expect(result).toContain("a.pdf");
  expect(result).toContain("12 lines");
  expect(result).toContain("doc_a"); // id handle present
  expect(result).toContain("b.txt");
  expect(result).toContain("parsing");
});
```

In `apps/web/convex/documents.test.ts`, find the test that queries `internal.documents.listForUser` (if present) and add assertions that each item has `sourceId` equal to the document's `_id` and a numeric `lineCount`. If no such test exists, add:

```ts
test("listForUser returns a sourceId handle and lineCount per document", async () => {
  const t = convexTest(schema, modules);
  const { t: alice, userId } = await asNewUser(t, "a@x.com");
  const storageId = await alice.run(async (ctx) =>
    ctx.storage.store(new Blob(["hi"], { type: "text/plain" })),
  );
  const docId = await alice.run(async (ctx) =>
    ctx.db.insert("documents", {
      userId, filename: "a.txt", kind: "txt", status: "ready",
      sizeBytes: 2, storageId, createdAt: 1,
    } as any),
  );
  await alice.mutation(internal.knowledge.insertChunks, {
    userId, entryId: "e1", source: "document", sourceId: docId,
    title: "a.txt", chunks: ["line one", "line two"],
  });

  const list = await t.query(internal.documents.listForUser, { userId });
  const row = list.find((d: any) => d.sourceId === docId);
  expect(row).toBeTruthy();
  expect(row.lineCount).toBe(2);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/web && npx vitest run convex/tools.test.ts convex/documents.test.ts`
Expected: FAIL — `listForUser` doesn't return `sourceId`/`lineCount`; tool output lacks the handle.

- [ ] **Step 3: Update `documents.listForUser`**

In `apps/web/convex/documents.ts`:
- Add the import at the top (near the other imports):
  ```ts
  import { lineCountsForUser } from "./knowledge";
  ```
- Replace the `listForUser` handler body (lines 66–79) with:

```ts
  handler: async (ctx, { userId }) => {
    const docs = await ctx.db
      .query("documents")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .order("desc")
      .collect();
    const lineCounts = await lineCountsForUser(ctx, userId);
    return docs.map((d) => ({
      sourceId: d._id,
      filename: d.filename,
      kind: d.kind,
      status: d.status,
      sizeBytes: d.sizeBytes,
      lineCount: lineCounts[d._id] ?? 0,
      createdAt: d.createdAt,
    }));
  },
```

- [ ] **Step 4: Update the `listDocuments` tool renderer**

In `apps/web/convex/tools.ts`, update the `listDocuments` `docs` type and line rendering:
- Extend the `docs` array element type to include `sourceId: string;` and `lineCount: number;`.
- Replace the `lines` map with:

```ts
    const lines = docs.map(
      (d) =>
        `- ${d.filename} (${d.kind}, ${formatBytes(d.sizeBytes)}, ${d.lineCount} lines${d.status !== "ready" ? `, ${d.status}` : ""}) [id: ${d.sourceId}]`,
    );
```

- [ ] **Step 5: Update the agent prompt (id handling)**

In `apps/web/convex/agent.ts`, in the instructions where `listDocuments` is described, append:
```
" listDocuments returns each document's id in [id: …]; use those ids only as sourceId arguments to readDocument/grep — do not show raw ids to the user."
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd apps/web && npx vitest run convex/tools.test.ts convex/documents.test.ts`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add apps/web/convex/documents.ts apps/web/convex/documents.test.ts apps/web/convex/tools.ts apps/web/convex/tools.test.ts apps/web/convex/agent.ts
git commit -m "feat(web): listDocuments surfaces sourceId handle + lineCount"
```

---

### Task 5: Full-suite gate + STATUS.md

**Files:**
- Modify: `STATUS.md`

- [ ] **Step 1: Run analyze + full test suite**

Run:
```bash
export PATH="/opt/homebrew/bin:$HOME/.pub-cache/bin:$PATH"
melos run analyze
melos run test
```
Expected: both clean. If analyze flags a leftover `pinpoint` reference, grep the tree (`grep -rn pinpoint apps/web/convex`) and remove it — there should be zero references outside git history.

- [ ] **Step 2: Update STATUS.md**

Add a C7 row/entry to `STATUS.md` recording: `readDocument` (positional read), `pinpoint`→`grep` (corpus-wide, line coordinates), `listDocuments` id handle + lineCount; `outline` deferred (parser stores no structure). Flip the marker to ✅ only after Step 1 is green; update "Last updated". Follow the existing STATUS.md format for the chat/web workstream.

- [ ] **Step 3: Commit**

```bash
git add STATUS.md
git commit -m "docs(status): C7 — document reader tools (readDocument + grep) code-complete"
```

---

## Self-Review

**Spec coverage:**
- readDocument (spec §1) → Task 2. ✓
- grep replacing pinpoint, scoped + corpus, line coordinates, ReDoS/window-merge preserved (spec §2) → Task 3. ✓
- listDocuments sourceId + lineCount (spec §3) → Task 4. ✓
- Backend queries corpusForUser + lineCounts (spec §Backend) → Task 1 (`corpusForUser`, `lineCountsForUser`). ✓
- Agent wiring + prompt (spec §Agent wiring) → Tasks 2/3/4 incrementally. ✓
- Security invariants (spec §Security) → asserted in every tool's "fails closed" test + internalQuery scoping tests. ✓
- Testing matrix (spec §Testing) → covered across Tasks 1–4. ✓
- outline out of scope → not planned; recorded in Task 5 STATUS note. ✓
- Rollout / analyze+test gate (spec §Rollout) → Task 5. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code; every test step shows real assertions. ✓

**Type consistency:**
- `reconstructedSourcesForUser` / `corpusForUser` return `{ sourceId, title, source, text }` — consumed with those exact keys in `grep` (Task 3) and the corpus test. ✓
- `lineCountsForUser` returns `Record<string, number>` — indexed as `lineCounts[d._id]` in Task 4. ✓
- `listForUser` new shape `{ sourceId, filename, kind, status, sizeBytes, lineCount, createdAt }` — matched by the `listDocuments` renderer type and both tests. ✓
- `grepSource(title, text, regex): string[]` — called with those args in `grep`. ✓
- Constants (`READ_MAX_LINES=200`, `READ_MAX_CHARS=8192`, `GREP_MAX_SOURCES=200`, `MAX_WINDOWS=40`, `MAX_PATTERN_LENGTH=200`) consistent between code and assertions. ✓
