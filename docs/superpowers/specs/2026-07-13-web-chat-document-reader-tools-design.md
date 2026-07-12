# C7 — Web chat document reader tools (readDocument + corpus-wide grep)

**Date:** 2026-07-13
**Status:** design (approved decisions captured; pending user spec review)
**Area:** `apps/web` (Convex agent tools + knowledge queries) — chat retrieval
**Builds on:** C2 (agentic chat), C4 (retrieval v2), C5 (listDocuments + dedup)

## Motivation

Today the chat agent has three tools ([`apps/web/convex/tools.ts`](../../../apps/web/convex/tools.ts)):

- `searchKnowledge` — semantic (embedding + BM25) search across all sources.
- `listDocuments` — enumerate the user's documents (name/kind/size/status).
- `pinpoint` — regex search **within one already-known source**, returning
  matched lines ± 2 lines of context.

This set cannot answer two ordinary requests:

1. **"Read the first line of each document"** — there is no *positional* read.
   `pinpoint` needs a pattern, and the model can't pattern-match content it
   hasn't seen. In practice the model calls `pinpoint` blindly, gets
   *"No matches found"*, and reports it couldn't read the documents.
2. **"Where does 'indemnity' appear across all my contracts?"** — `pinpoint`
   requires a `sourceId`; there is no exact/regex search *across* the corpus.
   `searchKnowledge` is cross-source but semantic, not exact.

The fix models the chat's document access on Claude Code's proven file toolkit —
`ls` + `cat` + `grep` + a semantic layer — where each tool is sharp and they
**compose** (grep locates a coordinate → read expands it → the model
summarizes/cites by line).

| Claude Code | Our tool | Change |
|---|---|---|
| `Read` (`offset`/`limit`, `cat -n`) | **`readDocument`** | **add** |
| `Grep` (optional path) | **`grep`** | **replace `pinpoint`** (generalize to cross-source + line numbers) |
| `ls` / Glob | **`listDocuments`** | **enhance** (expose `sourceId` handle + `lineCount`) |
| *(none — CC has no semantic search)* | `searchKnowledge` | keep as-is |

## Scope

**In scope**

1. `readDocument` — new positional, line-numbered read tool.
2. `pinpoint` → `grep` — generalize the existing regex tool to search across all
   sources (or one via optional `sourceId`) and emit line numbers.
3. `listDocuments` enhancement — surface each doc's `sourceId` and `lineCount`.
4. New/updated internal `knowledge` queries backing the above.
5. Agent registration + system-prompt guidance; unit tests for each tool.

**Out of scope**

- **`outline` tool** (section/heading map). The ingest parser flattens every
  format to raw text (`mammoth.extractRawText`, PDF pages merged, xlsx → CSV —
  see [`ingest.ts`](../../../apps/web/convex/ingest.ts)); no heading structure is
  stored. A useful outline needs the parser to capture structure first. Deferred
  to a future slice, gated on that parser work.
- The 3 duplicate `Kakeibo_Journal_EN_AR.pdf` entries — pre-existing uploads
  from before the C5 dedup guard; not a regression, not touched here.
- Any change to `searchKnowledge` or the retrieval pipeline.

---

## Terminology: "lines"

A source's text is reconstructed by `knowledge.linesFor`: it collects that
source's `knowledgeChunks`, sorts by `chunkIndex`, and joins `chunkText` with
`\n` (existing behavior — `pinpoint` already relies on it). "Lines" throughout
this spec means the result of `reconstructedText.split("\n")`, 1-indexed. Line
numbering is stable as long as chunk text and order are stable. This is the same
model `pinpoint` uses today, extended to be surfaced explicitly.

Both **documents and meetings** live in `knowledgeChunks`, so `readDocument` and
`grep` operate on **any `sourceId`** (document or meeting transcript), matching
`searchKnowledge`'s corpus-wide reach. `listDocuments` remains documents-only
(meetings have their own surface).

---

## 1. `readDocument` — positional, line-numbered read

**Purpose:** the `cat -n` of the corpus. Read a contiguous window of a known
source by line position.

**Input schema**

```ts
{
  sourceId: string,                 // document or meeting id (from listDocuments / grep / searchKnowledge)
  startLine?: number,               // 1-indexed, default 1
  maxLines?: number,                // default 50
}
```

**Behavior**

- Fail closed via `requireCallerUserId(ctx)` (same pattern as every other tool —
  `userId` comes from `ctx`, never from model input).
- Fetch reconstructed text via `internal.knowledge.linesFor({ userId, sourceId })`.
  Empty/missing → `"No content found for that document."`
- Clamp inputs defensively so the model can't request a runaway window:
  - `startLine` coerced to `>= 1` (non-positive → 1).
  - `maxLines` coerced to `>= 1` and capped at `MAX_LINES = 200`.
- Slice `lines[startLine-1 .. startLine-1+maxLines)`. If `startLine` is past the
  end → `"Document has only N lines."`
- Render each returned line prefixed with its 1-indexed number, right-aligned
  `cat -n` style, e.g. `   1  <text>`.
- **Hard char cap** `MAX_CHARS = 8192` on the *rendered* output: if exceeded,
  truncate at the cap and append `\n… (truncated)`. Guards against a single
  giant line (e.g. an xlsx CSV row) blowing up context.
- Prepend a one-line header naming the range actually returned, e.g.
  `<filename> — lines 1–1 of 240:` so the model (and the reader) know the window.

**"Read the first line" =** `readDocument({ sourceId, startLine: 1, maxLines: 1 })`.

## 2. `pinpoint` → `grep` — corpus-wide regex with coordinates

**Purpose:** the `grep` of the corpus. Find a regex across all sources, or within
one, returning **coordinates the model can expand** with `readDocument`.

**Input schema**

```ts
{
  pattern: string,                  // regex, case-insensitive
  sourceId?: string,                // omitted → search ALL the user's sources; present → scope to one
}
```

**Behavior**

- Fail closed via `requireCallerUserId(ctx)`.
- Keep `pinpoint`'s existing hardening: reject `pattern.length > MAX_PATTERN_LENGTH`
  (200) **before** compiling (ReDoS bound); invalid regex → `"Invalid search pattern."`
- **Scoped mode (`sourceId` present):** reconstruct that source via `linesFor`
  and scan — identical to today's `pinpoint`, plus line numbers.
- **Corpus mode (`sourceId` omitted):** fetch every source's reconstructed text
  for the user via a new `internal.knowledge.corpusForUser({ userId })`, which
  returns `Array<{ sourceId, title, source, text }>` (chunks grouped by source,
  each joined like `linesFor`). Scan each.
- For each source, split into lines and collect matches. Keep the existing
  **±2 context lines + overlapping-window merge** so shared context isn't
  duplicated. Prefix every emitted line with its number.
- Label each match block with its source coordinate header:
  `<title>:<firstLineNo>` (grep's `file:line`). A hit is now a coordinate the
  model hands to `readDocument({ sourceId, startLine })` to read the whole
  surrounding section — enabling *"summarize the part where it says xyz"* for
  exact phrases.
- Caps to bound cost/context:
  - `MAX_WINDOWS` merged windows total (existing constant, 40) across the whole
    result.
  - `MAX_SOURCES_SCANNED` (e.g. 200) sources in corpus mode; if the user has
    more, scan the first N and note the cap in the output (no silent truncation).
  - Reuse the 8 KB-class char cap on the assembled output.
- No matches → `"No matches found."`

**Migration:** `grep` fully subsumes `pinpoint`; `pinpoint` is removed (not left
beside `grep`) — mirroring Claude Code keeping Read and Grep separate but each
*general*, never two tools doing the same job. Callers: only the agent
registration and tests reference it.

## 3. `listDocuments` enhancement — expose the read/grep handle

`documents.listForUser` currently returns
`{ filename, kind, status, sizeBytes, createdAt }` per doc — no id, so the model
has nothing to pass to `readDocument`/`grep`. Change:

- `internal.documents.listForUser` also returns `sourceId: d._id` and
  `lineCount` (line count of the reconstructed text; requires a lightweight
  per-source line count — computed from the source's chunks).
- `listDocuments`'s rendered output includes the `sourceId` as a tool-handle per
  line. This is consistent with how the model **already** consumes raw
  `sourceId`s out-of-band from `searchKnowledge` (past the `<<<SOURCES>>>`
  marker) to drive `pinpoint` — it is trusted to use ids as *arguments*, not to
  print them. The tool description + a system-prompt line reinforce: "use the id
  only as a tool argument; do not display raw ids to the user."

**`lineCount` sourcing:** add `internal.knowledge.lineCountsFor` (or fold into a
single corpus metadata query) returning line counts per `sourceId` for the user,
so `listForUser` can annotate each doc without reconstructing full text in the
tool. Exact query shape decided in the plan; requirement: one batched query, not
N per-doc round-trips.

---

## Backend queries (in `apps/web/convex/knowledge.ts`)

- **`linesFor`** (exists) — unchanged; used by `readDocument` and scoped `grep`.
- **`corpusForUser`** (new, internalQuery) — `{ userId }` →
  `Array<{ sourceId, title, source, text }>`, each `text` the source's chunks
  sorted by `chunkIndex` and joined with `\n`. Backs corpus-mode `grep`.
- **`lineCountsFor`** (new, internalQuery) — `{ userId }` →
  `Record<sourceId, number>` (or array), line counts per source. Backs
  `listDocuments`' `lineCount`. May be derived from the same grouped scan as
  `corpusForUser` if the plan chooses to share one query.

All are `internalQuery` — reachable only server-side with a `userId` resolved
from the authenticated caller, never from client/model input (the established
security invariant).

## Agent wiring (`apps/web/convex/agent.ts`)

- Import/register `{ searchKnowledge, grep, listDocuments, readDocument }`
  (drop `pinpoint`).
- System prompt updated to describe the four tools and the compose loop:
  - `searchKnowledge` — fuzzy/topic questions.
  - `grep` — find exact values/phrases; across all sources or one; returns
    `title:line` coordinates.
  - `readDocument` — read specific lines of a known source (positional);
    "first line" = start 1, max 1; expand a `grep` hit by passing its line.
  - `listDocuments` — enumerate documents; use returned ids only as tool
    arguments, never shown to the user.

---

## Security & privacy

- Every tool fails closed without `ctx.userId`; no tool input carries a
  `userId`. Backing queries are `internalQuery`, scoped to the caller's `userId`
  on indexed lookups — unchanged invariant from C4/C5.
- Corpus-mode `grep` reads only the caller's own chunks (`by_user` index scoped
  to `ctx.userId`); no cross-tenant reach.
- Model-supplied regex bounded by `MAX_PATTERN_LENGTH` before compilation
  (ReDoS), preserved from `pinpoint`.
- Output char caps prevent a single pathological source/line from exhausting the
  context window.

## Testing

Mirror the existing direct-`execute` style in
[`tools.test.ts`](../../../apps/web/convex/tools.test.ts) (spread a `ctx` with a
mocked `runQuery`, invoke `tool.execute`).

**`readDocument`**
- default returns line 1 only, numbered, with the range header ("first line").
- `startLine`/`maxLines` return the requested window; numbering is correct.
- `maxLines` clamped to `MAX_LINES`; `startLine <= 0` coerced to 1.
- `startLine` past end → "only N lines" message.
- char cap truncates a single giant line and appends the truncation marker.
- empty/missing source → friendly message.
- fails closed without `ctx.userId`.

**`grep`**
- scoped mode (`sourceId` given) reproduces `pinpoint`'s match + ±2 context,
  now with line numbers, scoped to `ctx.userId`.
- corpus mode (no `sourceId`) scans multiple sources and labels each hit with
  `title:line`; scoped to `ctx.userId`.
- over-long pattern rejected before querying (ReDoS); invalid regex message;
  no-match message.
- fails closed without `ctx.userId`.

**`listDocuments`**
- output includes each doc's `sourceId` handle and `lineCount`.
- still scoped to `ctx.userId`; fails closed without it.

Backend query tests (convex-test, following `documents.test.ts` patterns) for
`corpusForUser` / `lineCountsFor` grouping + user scoping.

## Rollout

Single branch off `main` (e.g. `feat/web-chat-reader-tools`), merged `--no-ff`
when `melos run analyze` + `melos run test` are clean. Update `STATUS.md` (new
C7 row) as part of *done*.
