# C2 — Agentic chat over documents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A ChatGPT-like agentic chat on `apps/web`: per-user threads with streamed responses, an agent (`@convex-dev/agent` on OpenRouter) that calls `searchDocuments` (RAG over the user's docs via `@convex-dev/rag`) and `searchMeetings` tools, and in-chat document upload. Retires C1's custom `documentChunks` store for `@convex-dev/rag`.

**Architecture:** Register the `agent` + `rag` Convex components. `@convex-dev/rag` (namespace = `userId`) owns chunking/embedding/vector storage/search; ingestion keeps file parsing + feeds text to `rag.add` with our recursive chunker as the splitter. `@convex-dev/agent` owns threads/messages/streaming(DB deltas)/tool-loop, using an OpenRouter chat model; tools call `rag.search` and the meetings table. Client subscribes to streamed messages via Convex queries.

**Tech Stack:** `@convex-dev/agent`, `@convex-dev/rag`, `@ai-sdk/openai` (`createOpenAI` pointed at OpenRouter), `zod` (tool args), React + Vite, `convex-test` + `vitest`.

## Global Constraints

Security/privacy is top priority (standing directive):
- **`OPENROUTER_API_KEY`** (already set on the deployment) is used only server-side by the agent/rag/embedder; never client-side, never logged, never in a tool error string.
- **Per-user isolation everywhere:** `rag` **namespace = `userId`**; agent **threads owned by `userId`**. Every thread/message/tool function resolves `getAuthUserId` and rejects access to another user's thread (generic `"Not found"`). `searchDocuments`/`searchMeetings` scope to the caller. Isolation is TESTED (user B cannot read A's threads or retrieve A's docs/meetings).
- Tools run server-side; the model only ever receives the caller's own data.
- Tests-from-the-start: pure + convex-test authz layers run on a fresh clone (committed `_generated`), wired into the `apps/web` CI job. `/security-review` before merge. Conventional commits.

**Evolving-component caveat (READ):** `@convex-dev/agent` and `@convex-dev/rag` APIs change across versions and the snippets below are best-known-as-of-planning. For EACH component API call, the implementer MUST verify the exact export names + signatures against the INSTALLED package's types (`node_modules/@convex-dev/{agent,rag}/dist/*.d.ts`) and the official docs, and adapt (as C1 did for `pdf-parse` v2). Confirm the package name (`@convex-dev/agent` singular) at install. If an API differs materially from this plan, follow the installed API and note the deviation in the report — do not force the plan's literal snippet.

**Deploy gate (account-bound; USER runs):** after backend tasks land, the user runs `cd apps/web && npm install` + `npx convex dev` to register the new components, generate their `_generated` types, and deploy. convex-test/tsc for the new component code and live streaming verify after that (same pattern as C1). Agent then commits regenerated `_generated`.

**Verify (from `apps/web`):** `npx tsc --noEmit` · `npm run test` · `npm run build`.

---

## File Structure

```
apps/web/convex/
  convex.config.ts     # NEW: defineApp + app.use(agent) + app.use(rag)
  openrouter.ts        # NEW: createOpenAI({apiKey: env, baseURL: openrouter}) — shared provider
  rag.ts               # NEW: new RAG(components.rag, {embedding model, dimension}); add/search/remove helpers
  agent.ts             # NEW: new Agent(components.agent, {chat model, instructions, tools})
  tools.ts             # NEW: searchDocuments (rag.search) + searchMeetings (meetings table)
  chat.ts              # NEW: listThreads/createThread/listMessages(+syncStreams)/sendMessage — auth-gated
  ingest.ts            # CHANGED: parse -> rag.add (drop chunk+embed+insert)
  documents.ts         # CHANGED: remove -> rag delete by key + storage delete (drop chunk cascade)
  schema.ts            # CHANGED: remove documentChunks table + vector index
  ingestStore.ts       # CHANGED/REMOVED: chunk write-backs no longer needed (rag owns storage)
  lib/chunk.ts         # KEEP: used as rag custom splitter
  lib/embed.ts         # KEEP if reused by a custom embedder; else remove
apps/web/src/
  components/Chat.tsx   # NEW: thread list + streaming messages + composer + attach
  test/Chat.test.tsx    # NEW
  App.tsx               # CHANGED: add Chat to nav
```

---

## Task 1: Register components + RAG config + migrate ingestion off `documentChunks`

**Files:** Create `convex/convex.config.ts`, `convex/openrouter.ts`, `convex/rag.ts`. Modify `convex/ingest.ts`, `convex/documents.ts`, `convex/schema.ts`, `convex/ingestStore.ts`, `convex/documents.test.ts`, `apps/web/package.json`.

**Interfaces:**
- Produces: registered `agent`+`rag` components; `rag` instance + `ragAdd(ctx,{userId,key,text})` / `ragSearch(ctx,{userId,query,limit})` / `ragRemove(ctx,{userId,key})` helpers; ingestion that feeds `rag.add`; `documents.remove` that deletes the rag entry + file.

- [ ] **Step 1: Install + register components**

Run: `cd apps/web && npm install @convex-dev/agent @convex-dev/rag @ai-sdk/openai zod` (verify exact package names/versions resolve; note any substitutions).

`convex/convex.config.ts`:
```ts
import { defineApp } from "convex/server";
import agent from "@convex-dev/agent/convex.config";
import rag from "@convex-dev/rag/convex.config";

const app = defineApp();
app.use(agent);
app.use(rag);
export default app;
```
(Verify the component config import paths against the installed packages.)

- [ ] **Step 2: Shared OpenRouter provider**

`convex/openrouter.ts`:
```ts
import { createOpenAI } from "@ai-sdk/openai";

// One provider for chat + embeddings, server-only key.
export const openrouter = createOpenAI({
  apiKey: process.env.OPENROUTER_API_KEY,
  baseURL: "https://openrouter.ai/api/v1",
});
```

- [ ] **Step 3: RAG instance + helpers**

`convex/rag.ts` (verify `RAG` constructor + `add`/`search` signatures against installed types):
```ts
import { RAG } from "@convex-dev/rag";
import { components } from "./_generated/api";
import { openrouter } from "./openrouter";
import { chunkText } from "./lib/chunk";

export const rag = new RAG(components.rag, {
  textEmbeddingModel: openrouter.embedding("openai/text-embedding-3-large"),
  embeddingDimension: 3072,
});

// namespace == userId for per-user isolation.
export async function ragAdd(ctx: any, args: { userId: string; key: string; text: string }) {
  const chunks = chunkText(args.text); // reuse our recursive Arabic-aware splitter
  return rag.add(ctx, { namespace: args.userId, key: args.key, chunks });
  // If the installed rag.add wants { text, splitter } instead of pre-made chunks,
  // pass { text: args.text, splitter: chunkText } — verify against types.
}
export async function ragSearch(ctx: any, args: { userId: string; query: string; limit?: number }) {
  return rag.search(ctx, { namespace: args.userId, query: args.query, limit: args.limit ?? 8 });
}
export async function ragRemove(ctx: any, args: { userId: string; key: string }) {
  // Verify the delete-by-key API name (e.g. rag.delete / rag.remove).
  return rag.delete(ctx, { namespace: args.userId, key: args.key });
}
```

- [ ] **Step 4: Migrate ingest.ts to rag.add**

In `convex/ingest.ts`, keep `extractText` (unpdf/mammoth/xlsx). Replace the chunk+embed+insert block with:
```ts
const text = await extractText(doc.kind, buf);
if (text.trim().length === 0) throw new Error("No extractable text");
await ctx.runMutation/action(... ragAdd ...); // rag.add runs where ctx supports it — see note
await ctx.runMutation(internal.ingestStore.setReady, { documentId, chunkCount: /* from rag result if available, else 0 */ });
```
Note: `rag.add` may need an action or mutation ctx — check whether it runs in the `"use node"` action directly (it calls the embedding model → network, so the node action is fine) or must be a separate `rag`-context mutation. Adapt: simplest is to call `ragAdd` from within the existing `"use node"` ingest action (it already does network for embeddings). Set `chunkCount` from the rag result if it returns one; else keep the field but stop relying on the old chunk table.

- [ ] **Step 5: documents.remove → rag delete + file**

In `convex/documents.ts` `remove`: after ownership check, replace the `documentChunks` cascade with `await ragRemove(ctx, { userId, key: id })` then `ctx.storage.delete(doc.storageId)` + `ctx.db.delete(id)`. (Use the `documentId` as the rag `key` at ingest + delete so they match.)

- [ ] **Step 6: Drop documentChunks from schema + retire ingestStore chunk writes**

In `convex/schema.ts` remove the `documentChunks` table (+ vector index). In `convex/ingestStore.ts` remove `insertChunks` (keep `getDoc`/`setReady`/`setFailed`; `setReady`'s `chunkCount` may become 0 or a rag-provided count). Remove now-dead `lib/embed.ts` if unused (the rag embedder replaces it) — or keep if the custom embedder path reuses it; decide based on whether `openrouter.embedding(...)` works (preferred) vs a custom embedder.

- [ ] **Step 7: Update documents.test.ts**

The cascade test can no longer assert `documentChunks` emptiness (table gone). Change it to assert `remove` refuses another user's doc and deletes the row + calls the rag delete (stub/mock `rag` or assert the row is gone + no throw). Keep the isolation + unauthenticated + create-validation tests. Ensure the suite still runs under convex-test (mock the rag component calls in `ingest`/`remove` where the real component can't run headlessly — assert the namespace=userId + key were used).

- [ ] **Step 8: Verify (gated) + commit**

`npx tsc --noEmit` — expect stale-`_generated` errors for the new components until the deploy gate; ZERO real errors in the authored files. Report gate-vs-real. `npm run test -- documents` runs (mocked rag) where possible.
```bash
git add apps/web/convex apps/web/package.json apps/web/package-lock.json
git commit -m "feat(web): register agent+rag components; migrate ingestion to @convex-dev/rag (retire documentChunks)"
```

---

## Task 2: Agent + tools + chat functions (authz-tested)

**Files:** Create `convex/agent.ts`, `convex/tools.ts`, `convex/chat.ts`, `convex/chat.test.ts`.

**Interfaces:**
- Produces: `api.chat.{listThreads, createThread, listMessages, sendMessage}` (auth-gated, per-user threads); an `Agent` with `searchDocuments`+`searchMeetings` tools.

- [ ] **Step 1: Tools**

`convex/tools.ts` (verify `createTool` signature + how `ctx` exposes the calling user — the agent passes a ctx; resolve `userId` from it; if the tool ctx doesn't carry auth, thread the `userId` via the agent's per-call context/metadata — verify against docs):
```ts
import { createTool } from "@convex-dev/agent";
import { z } from "zod";
import { ragSearch } from "./rag";

export const searchDocuments = createTool({
  description: "Search the user's uploaded documents for relevant passages.",
  args: z.object({ query: z.string().describe("What to look for") }),
  handler: async (ctx, { query }) => {
    const userId = /* resolve caller userId from ctx (verify API) */;
    const { text } = await ragSearch(ctx, { userId, query });
    return text; // grounding text for the model
  },
});

export const searchMeetings = createTool({
  description: "Search the user's meetings by title and notes.",
  args: z.object({ query: z.string() }),
  handler: async (ctx, { query }) => {
    const userId = /* caller userId */;
    const rows = await ctx.runQuery(/* internal meetings.searchByUser */, { userId, query });
    return rows.map((m: any) => `- ${m.title}: ${m.notes ?? ""}`).join("\n") || "No matching meetings.";
  },
});
```
Add an internal `meetings.searchByUser({userId, query})` query (case-insensitive substring over title+notes, `by_user`-scoped).

- [ ] **Step 2: Agent**

`convex/agent.ts`:
```ts
import { Agent } from "@convex-dev/agent";
import { components } from "./_generated/api";
import { openrouter } from "./openrouter";
import { searchDocuments, searchMeetings } from "./tools";

export const chatAgent = new Agent(components.agent, {
  name: "Privoice Assistant",
  chat: openrouter.chat("openai/gpt-4o-mini"), // pick a strong default OpenRouter model; verify method name (.chat/.languageModel)
  instructions:
    "You are Privoice's assistant. Answer clearly and concisely. When the user asks about their documents or meetings, use the searchDocuments / searchMeetings tools and ground your answer in the results, noting the source. If a tool returns nothing relevant, say so instead of inventing facts.",
  tools: { searchDocuments, searchMeetings },
});
```

- [ ] **Step 3: Chat functions (auth-gated)**

`convex/chat.ts` — verify the exact thread/message/stream APIs against installed types; shape:
```ts
import { v } from "convex/values";
import { query, mutation, action } from "./_generated/server";
import { components } from "./_generated/api";
import { getAuthUserId } from "@convex-dev/auth/server";
import { chatAgent } from "./agent";
// import { vStreamArgs, listUIMessages, syncStreams } from "@convex-dev/agent"; // verify names

async function requireUserId(ctx: any) {
  const userId = await getAuthUserId(ctx);
  if (userId === null) throw new Error("Not authenticated");
  return userId;
}
// Threads are tagged with userId (via agent thread metadata / a side table mapping threadId->userId).
async function authorizeThread(ctx: any, threadId: string, userId: string) { /* verify owner or throw "Not found" */ }

export const listThreads = query({ args: {}, handler: async (ctx) => {
  const userId = await requireUserId(ctx);
  return /* agent.listThreads scoped to userId (verify API) or a threads side-table by_user */;
}});

export const createThread = mutation({ args: {}, handler: async (ctx) => {
  const userId = await requireUserId(ctx);
  const { threadId } = await chatAgent.createThread(ctx, { userId }); // verify how to associate userId
  return threadId;
}});

export const listMessages = query({
  args: { threadId: v.string(), paginationOpts: v.any(), streamArgs: v.any() /* vStreamArgs */ },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await authorizeThread(ctx, args.threadId, userId);
    // return listUIMessages(...) + syncStreams(...) per the streaming docs
  },
});

export const sendMessage = action({
  args: { threadId: v.string(), text: v.string() },
  handler: async (ctx, { threadId, text }) => {
    const userId = await requireUserId(ctx);
    await authorizeThread(ctx, threadId, userId);
    const { thread } = await chatAgent.continueThread(ctx, { threadId });
    await thread.streamText({ prompt: text }, { saveStreamDeltas: true }); // verify signature
  },
});
```
Associate `userId` with each thread (agent thread metadata if supported, else a `chatThreads` side table `{threadId, userId, title, createdAt}` indexed `by_user`) so `listThreads` + `authorizeThread` are user-scoped. Choose whichever the installed agent API supports; document the choice.

- [ ] **Step 4: convex-test authz/isolation tests**

`convex/chat.test.ts`: with two seeded users — A `createThread`; B's `listThreads` doesn't include it; B's `listMessages`/`sendMessage` on A's thread throw; unauthenticated calls throw. Mock/stub the agent+rag component calls where they can't run under convex-test (assert the ownership gate + that userId scoping is applied — the security-critical behavior), not the LLM. Keep assertions meaningful.

- [ ] **Step 5: Verify (gated) + commit**

`npx tsc --noEmit` (gate-only errors ok); `npm run test -- chat`. Commit:
```bash
git add apps/web/convex/agent.ts apps/web/convex/tools.ts apps/web/convex/chat.ts apps/web/convex/chat.test.ts apps/web/convex/meetings.ts
git commit -m "feat(web): chat agent + searchDocuments/searchMeetings tools + per-user thread functions + authz tests"
```

---

## Task 3: Chat UI (threads + streaming + composer + attach)

**Files:** Create `apps/web/src/components/Chat.tsx`, `apps/web/src/test/Chat.test.tsx`. Modify `apps/web/src/App.tsx` (nav).

- [ ] **Step 1: Failing component test**

`Chat.test.tsx` (mock `convex/react` + the agent React hooks): renders the thread list, renders messages from a mocked message list, typing + send calls the send mutation/action, the attach input is present. Keep warning-free.

- [ ] **Step 2: Implement Chat.tsx**

Thread sidebar (`useQuery(api.chat.listThreads)`, "New chat" → `createThread`), message view using the agent's React streaming hook (`useUIMessages(api.chat.listMessages, {threadId}, {initialNumItems, stream:true})` + `useSmoothText` for live text — verify hook names/import from the agent's React entry), a composer (textarea + Send → `useAction(api.chat.sendMessage)`), and an **attach** button (file input `.pdf,.docx,.xlsx,.txt,.md`) reusing the C1 upload: `generateUploadUrl` → POST → `documents.create` (the file enters the user's KB, searchable via the tool). Show a "Searching your documents…" affordance when a tool call is in progress if the hook exposes tool state. Calm-teal, light, theme tokens only.

- [ ] **Step 3: Nav**

In `App.tsx`, add **Chat** to the Meetings/Documents nav (Chat can be the default view). Keep sign-out in the shell.

- [ ] **Step 4: Verify + commit**

`npm run test` (all green, pristine), `npx tsc --noEmit`, `npm run build`.
```bash
git add apps/web/src
git commit -m "feat(web): agentic chat UI — threads, streaming messages, composer, in-chat upload"
```

---

## Task 4: Deploy gate, live e2e, security review, STATUS, finish

- [ ] **Step 1: Deploy gate (USER)** — `cd apps/web && npm install && npx convex dev` (registers agent+rag components, generates `_generated`, deploys; `OPENROUTER_API_KEY` already set). Report any component-registration or bundling error (adapt as needed, e.g. node vs default runtime for the embedder).
- [ ] **Step 2: Run gated tests + commit `_generated`** — `npm run test` (chat + documents authz green), `tsc` clean, `build` ok; `git add apps/web/convex/_generated && git commit -m "chore(web): regenerate _generated for agent+rag"`.
- [ ] **Step 3: Live e2e (USER, browser)** — sign in → Chat: (a) ask a general question → streamed answer; (b) upload a PDF **in chat**, then ask about its content → the agent calls searchDocuments and answers from it; (c) ask about a meeting by title → searchMeetings; (d) new thread + switch threads preserves history; (e) a second account sees none of the first's threads/docs. Report per step.
- [ ] **Step 4: `/security-review`** on the C2 diff — confirm key server-only; per-user namespace + thread ownership enforced + isolation-tested; no key in tool errors; no cross-tenant retrieval. Fix findings.
- [ ] **Step 5: STATUS.md** — C2 ✅ (verified after Step 3); note C1's store retired for `@convex-dev/rag`. Commit.
- [ ] **Step 6: Finish** — `superpowers:finishing-a-development-branch` → merge `feat/c2-chat` to `main` (`--no-ff`).

---

## Self-Review

**Spec coverage:** agent framework (@convex-dev/agent) → T2; rag retire+migrate C1 store → T1; tools searchDocuments+searchMeetings → T2; per-user threads + streaming → T2/T3; in-chat upload → T3; ChatGPT-like threads UI → T3; security (key server-only, namespace/thread per-user, isolation tested) → Global Constraints + T1/T2/T4; tests-from-start (authz convex-test now, live streaming at gate) → T2/T4; deploy gate + e2e + /security-review + STATUS + finish → T4. ✅

**Placeholder scan:** the code snippets contain intentional `/* verify ... */` markers because these components' exact APIs must be confirmed against the installed versions — each is paired with an explicit instruction to verify + adapt (not left vague). This is deliberate per the evolving-component caveat, not an unspecified TODO; the behavior required at each marker is stated.

**Type/name consistency:** `rag` namespace = `userId` and thread ownership = `userId` throughout; `ragAdd/ragSearch/ragRemove`, `chatAgent`, `api.chat.{listThreads,createThread,listMessages,sendMessage}`, tools `searchDocuments`/`searchMeetings` consistent across tasks. Document `key = documentId` used symmetrically in ingest add + remove.

**Risk note:** highest uncertainty is the exact `@convex-dev/agent`/`@convex-dev/rag` API surface (thread-userId association, tool ctx→userId, streaming query helpers, rag add/delete). Mitigated by the mandatory verify-against-installed-types instruction and by the deploy-gate live verification. If an API blocks a security guarantee (e.g. can't associate userId to a thread), escalate rather than ship a weaker isolation model.
