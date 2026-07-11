# C1 — Document ingestion + RAG store (web)

**Date:** 2026-07-12
**Status:** Approved design
**Workstream:** Privoice Cloud / Web — "chat over documents" sub-project, slice **C1** (ingestion). C2 (agentic chat) is a separate later sub-project. See STATUS.md + the cloud spec.

## Problem / goal

The web app needs a per-user **knowledge base**: a user uploads **PDF / XLSX / Word (.docx)** (plus `.txt`/`.md`) files; each is parsed, chunked, embedded, and stored so a later chat (C2) can retrieve relevant passages semantically. C1 delivers the whole ingestion pipeline + a **Documents** page (upload, live status, delete) — but **no chat yet**. It rests on O1 (auth + Convex on `apps/web`).

Decided in brainstorming: **RAG from the start** (chunk + embed + Convex vector search); **OpenRouter only** for both embeddings and (later) chat, via a single server-side `OPENROUTER_API_KEY` (the user has set this Convex env var); embeddings model `openai/text-embedding-3-small` (1536-dim) through OpenRouter's OpenAI-compatible `/embeddings` endpoint.

## Security & privacy (first-class — per standing directive)

- **`OPENROUTER_API_KEY` is a Convex deployment env var**, read only inside server actions, **never** sent to the client, **never** logged. No key literal in source.
- **Every function is identity-gated** (`getAuthUserId`, throws when null). `documents` and `documentChunks` are keyed by `userId`.
- **Vector search always filters `userId == caller`** (Convex vector-index `filterFields:["userId"]`) — semantic retrieval can never cross tenants. Tested for isolation.
- **Delete cascades**: removing a document deletes its chunks **and** the stored file blob — no orphaned content or vectors.
- **Minimal egress:** document text leaves Convex only to OpenRouter's embeddings endpoint (over HTTPS). No third parties. Parsed text + vectors are the only retained derivatives; document bytes stay in Convex file storage until the user deletes them.
- Uploads are size-capped (10 MB) and type-checked; failures are surfaced as a `failed` status with a reason, never a crash.
- `/security-review` on the C1 diff is part of definition-of-done.

## Data model (`apps/web/convex/schema.ts`, added tables)

```ts
documents: defineTable({
  userId: v.id("users"),
  storageId: v.id("_storage"),
  filename: v.string(),
  mimeType: v.string(),
  kind: v.string(),          // "pdf" | "docx" | "xlsx" | "txt" | "md"
  sizeBytes: v.number(),
  status: v.string(),        // "parsing" | "ready" | "failed"
  error: v.optional(v.string()),
  chunkCount: v.number(),    // 0 until ready
  createdAt: v.number(),
}).index("by_user", ["userId"]),

documentChunks: defineTable({
  userId: v.id("users"),
  documentId: v.id("documents"),
  chunkIndex: v.number(),
  text: v.string(),
  embedding: v.array(v.float64()),
})
  .index("by_document", ["documentId"])
  .vectorIndex("by_embedding", {
    vectorField: "embedding",
    dimensions: 1536,
    filterFields: ["userId"],
  }),
```

## Upload + async pipeline (Convex-idiomatic)

1. **Client:** `documents.generateUploadUrl` (mutation, auth-gated) → POST the file bytes to that URL → receive `storageId`.
2. **Client:** `documents.create({ storageId, filename, mimeType, sizeBytes })` (mutation) — validates auth + type + size (≤10 MB), infers `kind` from mimeType/extension, inserts a `documents` row `status:"parsing", chunkCount:0`, and **schedules** ingestion: `ctx.scheduler.runAfter(0, internal.ingest.ingestDocument, { documentId })`. Returns the id. (Reject unsupported type / oversize here with a thrown `ConvexError`.)
3. **Server (`convex/ingest.ts`, a `"use node"` internal action)** `ingestDocument({documentId})`:
   - Load the doc row (verify it exists); read the blob from storage (`ctx.storage.get`).
   - **Parse by `kind`** → plain text (see Parsing).
   - `chunkText(text)` → chunks.
   - **Embed** chunks via OpenRouter (batched); insert `documentChunks` rows (with `userId`, `documentId`, `chunkIndex`, `text`, `embedding`) through an internal mutation.
   - Set the doc `status:"ready", chunkCount:n`. On any throw: set `status:"failed", error:<message>` (message sanitized, no secrets).
   - The client's `documents.list` `useQuery` shows status transitions live.

Internal functions (`internal.*`) are used for the ingest write-backs so they aren't publicly callable.

## Parsing (Node action, per kind)

- **PDF** → `pdf-parse`. **DOCX** → `mammoth` (`extractRawText`). **XLSX** → `xlsx` (SheetJS): each sheet → CSV text, concatenated with sheet headers. **TXT/MD** → decode UTF-8 directly.
- Empty/garbled extraction → `failed` with a clear reason. These libs run only in the `"use node"` action.

## Chunking + embeddings

- **Pure helper** `chunkText(text, { maxChars = 3000, overlapChars = 300 })` in `convex/lib/chunk.ts` (deterministic, unit-tested; char-based to stay dependency-free — ~800 tokens ≈ 3000 chars). Splits on paragraph/whitespace boundaries where possible; never emits empty chunks; handles tiny + huge inputs.
- **Embeddings** `embedChunks(texts): Promise<number[][]>` in `convex/lib/embed.ts` — POSTs to `https://openrouter.ai/api/v1/embeddings` with `model:"openai/text-embedding-3-small"`, `input: texts` (batched ≤~96/req), `Authorization: Bearer ${process.env.OPENROUTER_API_KEY}`. Returns 1536-dim vectors in input order. Throws with a non-secret message on non-200.

## UI (`apps/web/src`)

- A **Documents** page reachable from a simple top nav alongside "Your meetings" (introduce minimal in-app nav: two views — Meetings, Documents — via local state or a tiny router; no heavy routing lib).
- **Upload:** file picker + drag-and-drop, `accept=".pdf,.docx,.xlsx,.txt,.md"`; shows the upload→parsing→ready/failed lifecycle.
- **List:** each doc = filename + kind icon + status chip (Parsing spinner / Ready / Failed+reason) + chunk count + Delete. Calm-teal, light. Empty state.
- Uses `useQuery(api.documents.list)` (live) + mutations for create/remove; upload via `generateUploadUrl` + `fetch` POST.

## Public functions (`apps/web/convex/documents.ts`)

- `generateUploadUrl` (mutation, auth) → `ctx.storage.generateUploadUrl()`.
- `create` (mutation, auth) → validate + insert + schedule ingest; returns id.
- `list` (query, auth) → caller's documents, newest first (`by_user`).
- `remove` (mutation, auth) → verify ownership (else `ConvexError("Not found")`), delete chunks (`by_document`), delete the storage blob, delete the row.
- `internal.ingest.*` — ingest action + the internal insert-chunks / set-status mutations (not public).

## Testing (from the start — per standing directive)

- **Unit (`convex/lib/chunk.test.ts`):** `chunkText` — respects max size, applies overlap, no empty chunks, handles empty string + a >100k-char input + a single short paragraph.
- **convex-test (`convex/documents.test.ts`):** `create` scopes to caller + schedules ingest; `list` isolation (two users, no cross-visibility); `remove` refuses another user's doc and cascades chunk deletion; unauthenticated calls throw. (Mock/stub the scheduled action; assert the row + scheduling, not the Node parse.)
- **Ingest action:** the `"use node"` parse+embed path (real `pdf-parse`/`mammoth`/`xlsx` + network to OpenRouter) is **not** unit-tested under convex-test; verified at the **deploy gate** with a real upload of one of each file type (status → ready, chunkCount > 0). `embedChunks` network call is exercised there. Vector retrieval is exercised in C2.
- Runs in the existing **`apps/web` CI job** (committed `_generated`); the ingest/embeddings path needs no live key to run the unit + convex-test layers.
- `/security-review` before merge.

## Components / files

- Modify: `apps/web/convex/schema.ts` (+`documents`, `documentChunks`).
- Create: `apps/web/convex/documents.ts`, `apps/web/convex/ingest.ts` (`"use node"`), `apps/web/convex/lib/chunk.ts`, `apps/web/convex/lib/embed.ts`, `apps/web/convex/lib/chunk.test.ts`, `apps/web/convex/documents.test.ts`.
- Create: `apps/web/src/components/Documents.tsx` + a minimal nav in `App.tsx` (Meetings ↔ Documents) + `apps/web/src/test/Documents.test.tsx`.
- Modify: `apps/web/package.json` (`pdf-parse`, `mammoth`, `xlsx` deps).
- Regenerate + commit `apps/web/convex/_generated` (tests-from-a-fresh-clone).
- `STATUS.md`.

## Account-bound steps (user)

`OPENROUTER_API_KEY` is already set on the deployment ✅. After scaffolding: `cd apps/web && npm install` (new parse deps) then `npx convex dev` (codegen + push the new tables/functions). Live upload verification at the deploy gate.

## Out of scope (C1)

The chat itself, the AI proxy, tool-calling, retrieval UX, meetings-in-chat, OCR of scanned/image PDFs, image files, doc re-embedding on model change, sharing/collaboration, pagination of huge doc lists.

## Decomposition note

**C2 (next sub-project — own brainstorm/spec/plan):** online AI proxy (Convex → OpenRouter, streamed via persist-and-subscribe) + agentic chat UI + tool-calling loop. First tool = `searchDocuments` (vector search over C1's `documentChunks`, user-scoped); later `searchMeetings`. Framework choice (e.g. Vercel AI SDK vs raw tool loop), streaming mechanism, and tool set are C2 brainstorm decisions.
