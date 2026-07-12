# C5 — Web chat UX polish + document de-duplication + document listing

**Date:** 2026-07-13
**Status:** design (approved decisions captured; pending user spec review)
**Area:** `apps/web` (React SPA + Convex backend) — chat + documents
**Builds on:** C2 (agentic chat), C3 (redesign), C4 (retrieval v2)

## Goal

Three focused improvements to the web chat/documents experience:

1. **Auto-scroll** — the message list follows the conversation: always snaps to
   the bottom when the user sends, and sticks to the bottom while the assistant
   reply streams in (as long as the user hasn't scrolled up to read history).
2. **Duplicate-document guard** — when the user uploads a file that is byte-for-byte
   identical to one they already have *and* has the same name, subtly ask before
   creating a second copy, offering to reuse the existing document instead.
3. **List-my-documents in chat** — asking the assistant to "list my documents"
   enumerates *every* uploaded document, not just the RAG-relevant matches.

Each is independent; they can ship as separate slices but share this spec.

---

## 1. Auto-scroll (stick-to-bottom)

**Behavior**
- On the user sending a message (optimistic echo appears): always scroll the
  message list to the bottom.
- While an assistant reply streams (message list grows / last message text
  changes): keep the bottom pinned **only if the user is already at/near the
  bottom** (within a ~64px threshold). If the user has scrolled up, do not yank
  them down; instead show a small "Jump to latest ↓" pill that scrolls to the
  bottom on click. This is the standard ChatGPT/Claude pattern.

**Where:** `src/features/chat/Chat.tsx` (the messages scroll container at the
`div.flex-1.overflow-y-auto` around line 325).

**Design**
- Add a `useStickToBottom` hook (new file `src/features/chat/use-stick-to-bottom.ts`)
  that owns:
  - a `ref` for the scroll container,
  - an `atBottom` boolean tracked from the container's scroll position
    (`scrollHeight - scrollTop - clientHeight <= THRESHOLD`), updated on `scroll`,
  - a `scrollToBottom(behavior)` imperative helper,
  - a `stick()` method that scrolls to bottom **iff** `atBottom` is currently true.
- In `Chat.tsx`:
  - Call `scrollToBottom("auto")` unconditionally inside `handleSend` (after the
    optimistic `pending` push) — the user's own send always jumps to bottom.
  - Call `stick()` in an effect keyed on the streamed content changing. The
    smallest reliable trigger is the concatenated length/text of the last
    message plus `pending.length`; a `useEffect` depending on
    `[messages, pending]` calling `stick()` covers both new turns and streaming
    deltas (each delta re-renders `messages`).
  - Render a "Jump to latest" pill (absolutely positioned, bottom-center of the
    canvas, above the composer) when `!atBottom && !isEmpty`.
- On thread switch (existing `useEffect` on `threadId`), scroll to bottom
  instantly so opening a conversation lands at the latest message.

**Isolation:** the hook is pure DOM/scroll logic, no Convex or app knowledge —
testable on its own and reusable.

**Testing**
- Unit test the hook's `atBottom` math and `stick()` gating (jsdom: fake a
  container with `scrollHeight`/`clientHeight`/`scrollTop`).
- Extend `src/test/Chat.test.tsx`: sending a message calls scroll-to-bottom;
  when scrolled up, a new streamed chunk does *not* force-scroll but the pill
  appears. (Mock `scrollTo`/`scrollTop` since jsdom doesn't lay out.)

---

## 2. Duplicate-document guard

**What counts as a duplicate:** same `filename` **and** identical content
(SHA-256 of the file bytes). Same name but changed content is *not* a duplicate
(it's a legitimate new version) and uploads normally.

**Data model:** add `contentHash: v.optional(v.string())` to the `documents`
table (`convex/schema.ts`). Optional so existing rows remain valid; legacy docs
without a hash simply never match as duplicates (acceptable — the guard applies
going forward). The hash is a hex SHA-256 string.

**Flow (client-side pre-flight, both upload paths):**
1. Before uploading, compute `contentHash = sha256(await file.arrayBuffer())`
   via `crypto.subtle.digest("SHA-256", …)` (new helper
   `src/features/documents/content-hash.ts`).
2. Look for an existing **ready or parsing** document in the already-loaded
   `documents` list with `filename === file.name && contentHash === hash`.
3. **If a match exists:** show a subtle confirmation (shadcn `Dialog`):
   > "You already have **{filename}** and it hasn't changed. Upload another copy?"
   with actions:
   - **Use existing** (default / primary) — no upload. On the Documents page this
     just closes with a toast ("Using your existing copy"). In chat, it attaches
     the *existing* document (pins its `docId`) to the pending message.
   - **Upload anyway** — proceeds with the normal upload, creating a second copy.
4. **If no match:** upload normally.

**Passing the hash through:** `documents.create` gains an optional
`contentHash: v.optional(v.string())` arg, stored on insert. Both callers
(`DocumentsList.upload` and `Chat.handleAttach`) compute and pass it.

**Server-side backstop:** `create` is *not* made to hard-reject duplicates —
the guard is a UX confirmation, and the user may legitimately choose "Upload
anyway." Server stays permissive; it only records the hash.

**Reusing the existing doc in chat ("reference documents"):** when the user
picks "Use existing" during an in-chat attach, push an `Attachment` built from
the existing document row (its `docId`, filename, kind, size) into
`pendingAttachments` — identical to what a fresh upload would produce — so the
message pins/grounds on the existing copy with no duplicate upload.

**New component:** `src/features/documents/DuplicateDialog.tsx` — a controlled
confirm dialog (open state + filename + onUseExisting/onUploadAnyway). Both the
Documents page and Chat render it and drive it through a small piece of local
state (the pending file + its detected duplicate).

**Testing**
- Unit: `content-hash.ts` produces a stable hex hash for known bytes.
- `convex/documents.test.ts`: `create` persists `contentHash`; omitting it is
  still valid.
- Component: `DuplicateDialog` renders the filename and fires the right callback
  per button. A DocumentsList/Chat test that a same-name+same-hash file opens the
  dialog and that "Use existing" performs no `create`.

---

## 3. List-my-documents in chat

**Problem:** `searchKnowledge` is semantic RAG search — "list my documents"
returns only chunks that happen to match the phrase, not the full inventory.

**Fix:** add a `listDocuments` agent tool (`convex/tools.ts`) that returns the
caller's full document inventory (name, kind, status, human-readable size,
created date) via a new internal query over the `documents` table, scoped by the
server-resolved `ctx.userId` (same `requireCallerUserId` pattern — no userId in
the tool's input schema). Documents only (per decision); meetings remain
searchable via `searchKnowledge`.

- Input schema: none (or an optional `kind` filter later — YAGNI for now).
- Returns a compact, model-friendly list (e.g. a formatted text block: one line
  per document with name · type · status). Failed/parsing docs are labeled so the
  assistant can note which aren't ready.
- Register in `agent.ts` `tools: { searchKnowledge, pinpoint, listDocuments }`
  and extend the instructions: *"When the user asks to list, count, or enumerate
  their documents (rather than asking a content question), use `listDocuments`
  and present the full list."*

**Internal query:** `internal.documents.listForUser({ userId })` (an
`internalQuery`) reusing the `by_user` index — kept internal so it's only
reachable from the tool with a server-resolved userId, never a client.

**Testing**
- `convex/tools.test.ts` (or `documents.test.ts`): `listForUser` returns only the
  caller's docs, ordered, with the expected fields; isolation across users holds.
- Instruction/wiring: the tool is registered and callable (agent-level tests
  follow the existing tool test style).

---

## Security & privacy

- `contentHash` is derived from the user's own file, stored only in their own
  per-user `documents` row; never leaves their scope. Client computes it locally
  (no extra network round-trip for detection — matches against the already-loaded
  list).
- `listDocuments` / `listForUser` are userId-scoped server-side exactly like the
  existing tools; the tool exposes no userId input, so the model cannot request
  another user's inventory. Fails closed if `ctx.userId` is absent.
- No change to the on-device-by-default mobile invariant — this is web/cloud only.

## Out of scope (YAGNI)

- Cross-name duplicate detection (same content, different name) — not requested;
  the rule is name+content.
- Server-side hard rejection / global dedup store.
- Meeting enumeration in `listDocuments` (kept documents-only).
- Backfilling `contentHash` for existing documents.

## Gate

`npx convex codegen` clean · `tsc` clean · all web tests pass (existing + new)
· `vite build` clean. Update STATUS.md (new C5 slice row + feature checklist).
Browser smoke of the three behaviors after the gate is green.
