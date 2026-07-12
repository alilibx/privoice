# Privoice Retrieval v2 — hybrid + rerank + pinning + citations

**Date:** 2026-07-12
**Status:** Approved design — ready for implementation plan
**Scope:** `apps/web` (Convex cloud stack) only. No mobile/Flutter changes.

## Goal

Replace the thin, vector-only retrieval behind the web chat with a **deterministic
retrieval pipeline** — hybrid candidate generation (BM25 + vector), rank fusion,
attachment/meeting **pinning**, an **LLM-judge rerank**, and a labeled **context
pack with citations** — over a **unified knowledge corpus** (documents *and*
meetings). The Agent reasons over the pack and answers with inline `[n]`
citations backed by a Sources list.

This operationalizes "RAG to find → rerank to sharpen → agent to reason → small
labeled context packs to stay honest." It is measurable via a retrieval eval
harness so quality is a number, not a vibe.

## Non-goals

- On-device / mobile RAG (separate future sub-project, S9) — different constraints.
- Cross-user or shared corpora; multi-tenant ACLs.
- Swapping the embedding model or the chat model selection (v1 already covers model choice).
- A learned/cross-encoder reranker service — the rerank is a single LLM-judge call.

## Approach (chosen)

**Deterministic pipeline behind the tools** (not agent-orchestrated multi-tool,
not a custom store). The Agent + client barely change; the intelligence lives in
one testable `convex/retrieval/` module invoked by a single `searchKnowledge`
tool (plus a separate `pinpoint` tool). Rejected alternatives: agent hand-rolls
retrieval each turn (non-deterministic, un-evalable, token-heavy); drop
`@convex-dev/rag` (reinvents vector store, migrations, chunking, `hybridRank`).

We lean on `@convex-dev/rag` 0.7.5 for: vector search, per-user namespaces,
`filterNames`/`filterValues` (pinning/scoping), `importance` (boost),
`chunkContext` (surrounding chunks), `hybridRank` (RRF fusion), `defaultChunker`,
dedup (`contentHashFromArrayBuffer`/`findEntryByContentHash`), and result/entry
metadata (citations). We build only: the BM25 arm (Convex full-text index over a
mirrored chunk table), the pipeline orchestration, the rerank call, the context
packer, meeting ingestion, and the eval harness.

## ⚠️ Task 1 gate — verify the fusion key

`hybridRank` fuses arrays of IDs; fusion needs a **shared key** between the
vector list (`rag.search` results) and the BM25 list (`knowledgeChunks` rows).
**The first implementation task inspects the installed `rag.search` result shape**
(`node_modules/@convex-dev/rag`) and defines that key:

- Preferred: **chunk-level** via a stable `(entryId, chunkIndex)` pair (or a
  chunk id the component exposes), so fusion ranks chunks.
- Fallback (committed default if no stable chunk key exists): **entry-level**
  fusion — map both lists to `entryId`, dedupe preserving order, fuse entry
  rankings, then assemble the pack from each top entry's best chunks (by vector
  score / BM25 hit). Nothing downstream blocks on chunk-level.

The rest of the design is written to work with either; only `fuse()`'s key
extraction differs.

## Unified knowledge corpus

- **One RAG namespace per user** (unchanged: `namespace = userId`). Every entry
  is tagged with `filterValues` for `source: "document" | "meeting"` and
  `sourceId` (the `documents._id` / `meetings._id`). RAG is constructed with
  `filterNames: ["source", "sourceId"]`.
- **Documents**: ingested as today (parse → chunk → `rag.add`), now also writing
  the BM25 mirror (below) and the `source`/`sourceId` filter values.
- **Meetings**: **newly ingested into RAG** — title + notes + transcript (when
  present) chunked and added, tagged `source: "meeting"`. This replaces the
  title/notes-only `searchByUser`. A one-time **backfill** re-ingests existing
  meetings (an internal migration action iterating the user's meetings).
- Meetings re-ingest on update (notes/transcript change) via the same path,
  keyed by `meetingId` so `rag.add` replaces rather than duplicates.

## BM25 arm — `knowledgeChunks` table

The component's chunk store is internal, so we mirror searchable text:

```ts
knowledgeChunks: defineTable({
  userId: v.id("users"),
  entryId: v.string(),        // the rag entry id this chunk belongs to
  source: v.string(),         // "document" | "meeting"
  sourceId: v.string(),       // documents._id | meetings._id
  title: v.string(),
  chunkText: v.string(),
  chunkIndex: v.number(),
})
  .index("by_user", ["userId"])
  .index("by_source", ["userId", "source", "sourceId"])
  .searchIndex("by_text", { searchField: "chunkText", filterFields: ["userId", "source"] })
```

- Written in the **same transaction path** as `rag.add` during ingestion (docs +
  meetings), one row per chunk, with the same chunk boundaries.
- Deleted alongside RAG removal in `documents.remove` / meeting delete / re-ingest
  (delete-by `by_source`).
- BM25 search: `ctx.db.query("knowledgeChunks").withSearchIndex("by_text", q =>
  q.search("chunkText", query).eq("userId", userId))` with an optional
  `.eq("source", …)` when type-filtered; take top ~20.

## Retrieval pipeline — `convex/retrieval/`

`retrieve(ctx, { userId, query, sourceFilter?, pinnedSourceIds?, config })
→ { pack: string, sources: SourceRef[] }`

Stages (each a small, independently testable function):

1. **candidates** — run vector (`rag.search`, `limit: config.candidateK`,
   `chunkContext: config.chunkContext`, `vectorScoreThreshold`) and BM25
   (`knowledgeChunks` search, `config.candidateK`) concurrently. Each yields
   chunk candidates `{ key, entryId, source, sourceId, title, text, score }`.
2. **fuse** — `hybridRank([bm25Keys, vectorKeys], { weights: config.fuseWeights,
   k: config.rrfK })`; reorder the unified candidate set by fused rank.
3. **pinAndBoost** — candidates whose `sourceId ∈ pinnedSourceIds` (the just-
   attached docs / active meeting) are boosted to the front and always retained
   (inclusive). Global candidates remain — cross-doc questions still work. (RAG
   `importance` is set high at ingest for pinned-at-upload docs; the pipeline
   also re-orders here so pinning works even when importance isn't enough.)
4. **rerank** (config-gated, default on) — one LLM-judge call: cheap fixed model
   (`config.rerankModel`, e.g. a low-cost OpenRouter model) is given the query +
   the fused top `config.rerankPool` (~30) numbered candidates and returns the
   best `config.keepN` (5–8) indices, best first. On any error/timeout → skip,
   keep fused order (fail-soft).
5. **pack** — take the kept chunks, number them `[1..n]`, and build:
   - `pack`: a labeled briefing string — a one-line route header, then each
     chunk as `"[n] <title> — <section/timestamp>\n<text>"`, best first, capped
     at `config.tokenBudget`.
   - `sources`: `SourceRef[] = { n, source, sourceId, title, locator }`
     (`locator` = section/heading for docs, timestamp for meetings).

Config in `convex/retrieval/config.ts` (server-side only): `candidateK`,
`fuseWeights`, `rrfK`, `chunkContext {before, after}`, `vectorScoreThreshold`,
`rerankEnabled`, `rerankModel`, `rerankPool`, `keepN`, `tokenBudget`.

## Tools

- **`searchKnowledge`** (`inputSchema: { query, source?: "document"|"meeting" }`)
  — resolves `userId` from `ctx.userId` (server-injected, unchanged security
  model), reads the caller's pinned source ids (from the current turn — see
  Pinning), runs `retrieve()`, returns a string containing the `pack` **and** a
  machine-readable trailing `sources` block (JSON) so the value is both readable
  by the model and parseable by the client from the tool part output. Replaces
  `searchDocuments` + `searchMeetings`.
- **`pinpoint`** (`inputSchema: { sourceId, pattern }`) — exact/regex match over
  one entry's mirrored `chunkText` (via `by_source`), returns matching lines with
  ±2 lines of context. Used for precise anchors after `searchKnowledge` narrows.

## Pinning attachments through the turn

The web client already appends a grounding note naming attached files
(`attachment-prompt.ts`). v2 makes this structural: `sendMessage` gains an
optional `pinnedSourceIds: string[]` arg (the attached `documentId`s / active
meeting id), validated server-side to belong to the caller, and passes them into
the agent generation context so `searchKnowledge` can read them for
`pinAndBoost`. The natural-language grounding note is retained as a secondary
nudge. (Exact mechanism for surfacing `pinnedSourceIds` to the tool — via the
agent's per-call context — is settled in the plan; fallback is to prepend the
pinned ids into the tool's reach through the same server-resolved path used for
`userId`.)

## Citations

- `searchKnowledge` returns `sources[]`; the Agent instructions are updated to:
  "Ground every claim in the provided context. Cite with `[n]` matching the
  numbered sources. Never cite a source not provided; if the context is
  insufficient, say so."
- **Client:** the chat reads the tool part's output from `message.parts` (same
  channel `ToolTrace` uses), parses the `sources` block, and:
  - renders a **Sources** list under the assistant message (`[n] title —
    locator`, linking to the document/meeting), and
  - linkifies `[n]` markers in the Markdown answer (a `Markdown` post-step or a
    custom `text`/link renderer) to scroll to the matching source.
- If no `sources` are present (no tool call), render nothing (unchanged).

## File structure

```
apps/web/convex/
  retrieval/
    config.ts            # tunable knobs (server-only)
    candidates.ts        # vector + BM25 candidate generation
    fuse.ts              # hybridRank wrapper + fused key extraction (Task 1)
    rerank.ts            # LLM-judge rerank (fail-soft)
    pack.ts              # context pack + SourceRef assembly
    retrieve.ts          # orchestrates the pipeline; exports retrieve()
    types.ts             # Candidate, SourceRef, RetrievalConfig
  knowledge.ts           # knowledgeChunks writes/deletes/search helpers
  tools.ts               # searchKnowledge + pinpoint (replaces searchDocuments/Meetings)
  ingest.ts              # + write knowledgeChunks; unchanged parse/chunk otherwise
  meetings.ts            # + ingestMeeting + backfill migration
  schema.ts              # + knowledgeChunks table
  chat.ts                # sendMessage gains pinnedSourceIds; agent instructions
  rag.ts                 # RAG constructed with filterNames [source, sourceId]
apps/web/src/features/chat/
  Sources.tsx            # renders SourceRef[] under an assistant message
  Markdown.tsx           # linkify [n] markers
  Chat.tsx               # pass pinnedSourceIds to sendMessage; render Sources
apps/web/convex/retrieval/*.test.ts
apps/web/src/test/*      # Sources + citation rendering tests
```

## Eval harness (retrieval quality)

- `convex/retrieval/eval.test.ts` (convex-test): seed a small fixed corpus
  (2–3 documents + 2–3 meetings with known content) into a user's namespace via
  the real ingest path (with a stubbed embedding model so it's deterministic and
  offline), then assert a fixtures table `{ query, expectedSourceIds }`:
  - **recall@k**: the expected source appears in the packed sources for each query.
  - **citation-correctness**: every `SourceRef.sourceId` returned exists in the
    seeded corpus (no fabricated sources).
  - **attachment golden**: with a freshly-added doc pinned, a vague query
    ("what is this") returns that doc as the top source — the exact bug this fixes.
- Rerank is stubbed/bypassed in eval (no network); fusion + pinning + packing are
  exercised for real. A separate opt-in, non-CI script can measure with the real
  rerank model.
- Wire into the existing web `vitest` CI. Report metrics; fail on regressions
  below a threshold agreed in the plan.

## Error handling / fail-soft

- BM25 index empty or throws → vector-only candidates (pipeline continues).
- Vector search throws → BM25-only; if both fail → tool returns "no results"
  (agent says it can't find it — never invents).
- Rerank error/timeout → skip, keep fused order.
- OpenRouter unreachable (embeddings/rerank) → surfaced as a clear error to the
  client; no silent wrong answer.
- Ingestion failures already mark the document `failed`; meeting ingest failures
  are logged and retried on next update.

## Security invariants (unchanged, reaffirmed)

- `userId` is server-resolved (`ctx.userId`), never client-supplied; every
  retrieval query and `knowledgeChunks` read is `userId`-scoped.
- `pinnedSourceIds` are validated server-side to belong to the caller before use.
- `OPENROUTER_API_KEY` stays server-only (embeddings + rerank calls).
- `knowledgeChunks` is per-user and ownership-checked on every access.

## Testing

- Unit: `fuse` (RRF ordering + weights), `pinAndBoost` (pinned always retained,
  globals preserved), `pack` (numbering, ordering, budget, SourceRef shape),
  `rerank` (fail-soft path), `knowledge` (search + delete-by-source).
- Integration (convex-test): ingest writes both RAG + `knowledgeChunks`;
  `documents.remove` cleans both; `searchKnowledge` returns pack + sources;
  `pinpoint` finds anchors.
- Eval harness as above.
- Client: `Sources` renders `SourceRef[]`; `[n]` markers linkify; existing chat
  tests stay green.
- Gate: `tsc -b`, `npm test`, `npm run build` all green; `melos run analyze` clean.

## Rollout

Full spec, **built straight through** (one continuous implementation pass; final
whole-branch review at the end, no phase gates). Task 1 (fusion-key verification)
first, then corpus/schema, ingestion, pipeline stages, tools, chat/client
citations, eval, verification. On completion, add a **C4 — Retrieval v2** slice
to STATUS.md, ✅ only after the gate + eval pass.
