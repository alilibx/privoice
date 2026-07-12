# C2 — Agentic chat over documents (web)

**Date:** 2026-07-12
**Status:** Approved design
**Workstream:** Privoice Cloud / Web — "chat over documents" sub-project, slice **C2** (the chat). Builds on C1 (ingestion) and O1 (auth). Retires C1's custom vector store in favor of `@convex-dev/rag`.

## Problem / goal

A ChatGPT-like, **agentic** chat on the web app: the user chats with an assistant that can **search their uploaded documents** (RAG) and **their meetings** as tools it decides when to call, streams responses token-by-token, keeps durable per-user conversation history, and lets the user **upload documents from within the chat** (no need to visit the Documents tab). General questions are answered directly; document/meeting questions are grounded via retrieval.

## Decisions (from brainstorming)

- **Agent framework:** `@convex-dev/agent` — threads, messages, durable history, tool-calling loop, **streaming via DB deltas over websockets** (resilient to dropped connections, multi-client). Model provider: **OpenRouter** via the AI SDK provider, reusing the single `OPENROUTER_API_KEY`.
- **Retrieval:** **`@convex-dev/rag`** component with **namespace = `userId`** for per-user isolation. This **replaces C1's custom `documentChunks` vector store**.
- **Tools:** `searchDocuments` (rag.search over the user's docs) and `searchMeetings` (the user's web meetings' title+notes — thin until web meeting capability lands, but wired now). **No web-search tool.**
- **In-chat upload:** reuses the ingestion pipeline (upload → parse → `rag.add`); an attached file enters the user's knowledge base and is immediately searchable. The Documents tab remains the library/manager.
- **Conversation model:** multiple named threads (ChatGPT-like), listed + selectable, per user.
- Embeddings stay **`text-embedding-3-large`** (3072-dim) via OpenRouter.

## What this changes in C1 (migration)

- **Keep:** the `documents` table (upload + metadata + status), file **parsing** (`unpdf`/`mammoth`/`xlsx` → text), the Documents page, and the recursive **Arabic-aware `chunkText`** — now passed to the RAG component as its **custom splitter**.
- **Retire/replace:** the `documentChunks` table + its vector index, the direct `embed.ts` call, and the custom `vectorSearch`. Ingestion (`ingest.ts`) changes from "chunk → embed → insert `documentChunks`" to **`rag.add({ namespace: userId, key: documentId, text, splitterOptions/custom splitter })`**. `documents.remove` deletes the RAG entry (by key) + the file, instead of cascading `documentChunks`.
- **Re-ingestion:** existing uploaded docs must be re-uploaded (their content moves into the RAG component's store). Dev data — acceptable.
- The `documents.test.ts` cascade test changes from "chunks deleted" to "rag entry removed" (assert via the RAG component's API or a stubbed rag).

## Data / backend

- **Convex components** registered in `convex/convex.config.ts`: `agent` + `rag`.
- **`rag`** configured with the OpenRouter embeddings model (`text-embedding-3-large`, 3072-dim). If the AI SDK OpenRouter provider doesn't expose an embedding model, provide a **custom embedder** adapter that calls OpenRouter's `/embeddings` (reusing the C1 `embedChunks` logic). Namespace per user.
- **`agent`** configured with an OpenRouter chat model (a sensible default, e.g. a strong general model) + a system prompt (concise, grounds in tool results, cites which doc/meeting a fact came from when it used a tool). Threads are created per user; messages persisted by the component.
- **Tools** (AI SDK tool definitions the agent can call), each resolving the calling user server-side:
  - `searchDocuments({ query, k? })` → `rag.search({ namespace: userId, query, limit })` → returns top chunks (text + source doc) for the model to ground on.
  - `searchMeetings({ query })` → queries the user's `meetings` (title+notes) — simple text match for now (vector later).
- **Chat functions** (`convex/chat.ts`, all auth-gated):
  - `listThreads` (query) → user's threads newest-first.
  - `createThread` (mutation) → new thread for the user.
  - `listMessages({ threadId })` (query) → messages + streaming deltas for a thread the user owns.
  - `sendMessage({ threadId, text })` (mutation/action) → appends the user message and kicks the agent's streamed, tool-using response (persisted via the component).
  - Ownership checks on every thread access (a user can only see/use their own threads).
- **In-chat upload** reuses `documents.generateUploadUrl` + `documents.create` (which now feeds `rag.add`); no new upload path.

## Web UI (`apps/web/src`)

- A **Chat** view added to the nav (Meetings · Documents · **Chat**), likely the primary surface.
- **Thread sidebar/list** (new chat, select thread) + **message view** (user/assistant bubbles, assistant text streaming in live via the agent's delta subscription, tool-call indicator e.g. "Searching your documents…") + **composer** (textarea, send) with an **attach** button (file picker `.pdf,.docx,.xlsx,.txt,.md`) that uploads into the KB and shows the doc becoming available.
- Calm-teal, light. Streaming uses `useQuery` on the thread's messages/deltas (no manual SSE).

## Security & privacy (first-class — per standing directive)

- `OPENROUTER_API_KEY` server-only (agent + rag + embedder), never client/logged. No key in tool errors.
- **Per-user isolation everywhere:** rag `namespace = userId`; agent threads owned by `userId` (every thread/message function checks ownership → generic "Not found" on mismatch); `searchMeetings`/`searchDocuments` scope to the caller. Tested for isolation (user B can't read A's threads, can't retrieve A's docs).
- Tools run server-side; the model only ever receives the caller's own data. Retrieved content flows to the model (allowed); no cross-tenant leakage.
- Minimal retention: conversation history is the feature; documents already governed by C1. `/security-review` before merge.

## Testing (from the start — per standing directive)

- **Unit:** any pure helper (e.g. tool-arg parsing, meeting text-match ranking) tested directly.
- **convex-test:** thread/message **authz + isolation** (create thread as A; B's `listThreads`/`listMessages` can't see it; `sendMessage` to A's thread as B throws); `searchDocuments`/`searchMeetings` tools scope to the caller (stub/mocked rag where the component can't run under convex-test — assert the namespace/userId passed). The live LLM streaming + real `@convex-dev/agent`/`@convex-dev/rag` runtime are **verified at the deploy gate** (they need the live key + deployed components), consistent with C1's node-path approach.
- **Web:** component tests (mocked convex) — thread list renders, composer sends, streaming message renders from mocked deltas, attach triggers upload.
- Runs in the `apps/web` CI job (committed `_generated`). `/security-review` gate.

## Components / files (indicative)

- `apps/web/convex/convex.config.ts` — register `agent` + `rag` components.
- `apps/web/convex/rag.ts` — configure rag (OpenRouter embeddings, custom splitter = `chunkText`); helpers for add/search/remove.
- `apps/web/convex/agent.ts` — configure the agent (OpenRouter model, system prompt, tools).
- `apps/web/convex/tools.ts` — `searchDocuments`, `searchMeetings` tool defs.
- `apps/web/convex/chat.ts` — listThreads/createThread/listMessages/sendMessage (auth-gated).
- `apps/web/convex/ingest.ts` — swap chunk+embed+insert for `rag.add` (keep parsing).
- `apps/web/convex/documents.ts` — `remove` deletes the rag entry + file (drop chunk cascade).
- `apps/web/convex/schema.ts` — remove `documentChunks` table + vector index (component owns storage now).
- Delete/retire: `apps/web/convex/lib/embed.ts` direct-call usage (may keep the OpenRouter embed fn if the custom rag embedder reuses it); custom vectorSearch (none shipped yet).
- `apps/web/src/components/Chat.tsx` (+ thread list, message view, composer, attach) + `App.tsx` nav; tests.
- `STATUS.md`.

## Out of scope (C2)

Web meeting capability (audio→STT→minutes on web — separate slice; `searchMeetings` stays title+notes until then), web-search tool, per-conversation document scoping (uploads go to the user's global KB), voice input, message editing/branching, sharing conversations, billing/rate limits (O2), mobile chat client.

## Decomposition note

C2 is one sub-project built in tasks: (1) register components + rag config + migrate ingestion off `documentChunks`; (2) agent config + tools (searchDocuments/searchMeetings) + chat functions with authz tests; (3) chat UI (threads/stream/composer/attach); (4) deploy gate + live streaming e2e + `/security-review` + STATUS + merge.
