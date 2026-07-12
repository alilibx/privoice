# C6 — Delete chat (conversation) on web

**Date:** 2026-07-13
**Status:** design (approved decisions captured; pending user spec review)
**Area:** `apps/web` — chat conversation rail + Convex chat backend
**Builds on:** C2 (agentic chat / threads), C5 (chat UX)

## Goal

Let a user delete a conversation from the chat rail. Deleting a chat removes
both our ownership record (`chatThreads` row) and the agent component's stored
messages/streams for that thread, gated so a user can only ever delete a thread
they own.

## Decisions (from brainstorm)

- **Trigger:** a per-row kebab (`⋯`) menu in the conversation rail with a
  **Delete** item (menu leaves room for a future "Rename").
- **Guard:** a **confirm dialog** ("Delete this conversation? This can't be
  undone." → Cancel / Delete). True delete happens only on confirm.
- **After deleting the active thread:** open the **most recent remaining**
  thread; if none remain, fall to the empty state.

## Backend

**New mutation `chat.deleteThread({ threadId })`** in `convex/chat.ts`:
1. `const userId = await requireUserId(ctx)`.
2. `await authorizeThread(ctx, threadId, userId)` — reuses the existing
   ownership gate; throws `"Not found"` on any mismatch (never reveals another
   user's thread).
3. Look up our `chatThreads` row by `by_thread` and `ctx.db.delete(row._id)`.
4. `await chatAgent.deleteThreadAsync(ctx, { threadId })` — the agent
   component's own API (verified in `@convex-dev/agent` d.ts) that deletes the
   thread's messages and streams in batches (safe from a mutation ctx).

Ordering: delete our ownership row first, then kick off the agent-side async
delete. If the agent delete somehow fails, the thread is already gone from the
user's list (no orphan visible); the agent component's batched delete is
idempotent by threadId.

**Security:** identical posture to the rest of `chat.ts` — `userId` resolved
server-side, `authorizeThread` enforces ownership, generic `"Not found"` on
mismatch. No client-supplied userId anywhere.

## Frontend

**`ThreadList.tsx`** — add an `onDelete(threadId)` prop. On each row, render a
kebab (`MoreHorizontal`) button that opens a `DropdownMenu` with a destructive
**Delete** item. The kebab is visible on hover (desktop) and on the active row,
and always visible on touch (no hover) — achieved with `opacity` +
`group-hover`/`aria-current` styling, matching the row's existing active
treatment. The row stays a button for selection; the kebab is a sibling control
(not nested in the row button, to keep valid markup) positioned at the row's
right edge. Clicking the kebab must not trigger row selection (stop
propagation).

**`Chat.tsx`** — owns the confirm flow and the mutation call:
- `const deleteThread = useMutation(api.chat.deleteThread)`.
- Local state `pendingDelete: string | null` (the threadId awaiting confirm).
- `ThreadList`'s `onDelete={(id) => setPendingDelete(id)}`.
- A confirm dialog (reuse the shadcn `Dialog`, same pattern as
  `DuplicateDialog`) titled "Delete conversation" with body "This conversation
  and its messages will be permanently deleted. This can't be undone." and
  Cancel / **Delete** (destructive) buttons.
- On confirm: call `deleteThread({ threadId })`; on success, if the deleted id
  was the active `threadId`, recompute the next selection from the (soon
  reactively-updated) thread list — set `threadId` to the most recent remaining
  thread's id, or `null` if none. Because `threads` is a live `useQuery`,
  compute the "next" id from the current `threads` array excluding the deleted
  id at call time, then `setThreadId(next)`. Close the dialog. Toast on error.

**Empty state:** already handled — `isEmpty` + auto-select effect. When
`threadId` becomes `null` and no threads remain, the existing `EmptyState`
renders; if threads remain, the existing auto-select effect (or our explicit
`setThreadId(next)`) picks one.

## Testing

**Backend (`convex/chat.test.ts`):**
- `deleteThread` removes the caller's `chatThreads` row (assert it's gone from
  `listThreads`). Mock/stub the agent component the same way existing chat
  tests handle `chatAgent` (the suite already avoids exercising the headless
  agent runtime — follow its established approach; if it calls real
  `chatAgent`, inject/monkeypatch `deleteThreadAsync` to a spy so the row-delete
  logic is what's under test).
- Authorization: a second user calling `deleteThread` on the first user's
  threadId throws `"Not found"`, and the row still exists.

**Frontend:**
- `ThreadList` test: rows render a delete affordance; activating it calls
  `onDelete` with the row's threadId (extend `src/test/` — there isn't a
  ThreadList test yet; add `ThreadList.test.tsx`).
- `Chat.test.tsx`: opening the kebab → Delete shows the confirm dialog;
  confirming calls the `deleteThread` mutation with the threadId. (Mock
  `useMutation` for `api.chat.deleteThread` like the existing mocks.)

## Out of scope (YAGNI)

- Rename thread (menu is structured to allow it later, not building it now).
- Bulk delete / "clear all conversations".
- Undo / soft-delete (decision was hard delete + confirm).
- Archiving.

## Gate

`npx convex codegen` clean · `tsc` clean · all web tests pass (existing + new)
· `vite build` clean. Update STATUS.md (C6). Browser smoke: delete a
conversation (active + non-active), confirm it disappears, its messages are
gone, and selection lands correctly.
