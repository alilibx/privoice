# C6 — Delete Chat (Conversation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user delete a conversation from the chat rail — removing both our `chatThreads` ownership row and the agent component's messages/streams — behind a confirm dialog, ownership-gated.

**Architecture:** A new ownership-gated `chat.deleteThread` mutation deletes our row then calls `chatAgent.deleteThreadAsync`. The `ThreadList` gains a per-row kebab (`⋯`) menu with a destructive Delete item that calls an `onDelete` prop; `Chat` owns the confirm dialog + mutation call and re-selects the most recent remaining thread when the active one is deleted.

**Tech Stack:** React + Vite, TypeScript, Convex (mutation + `@convex-dev/agent` `deleteThreadAsync`), shadcn/ui (DropdownMenu, Dialog, Button), Vitest + Testing Library.

## Global Constraints

- **Directory:** all work under `apps/web/`; run commands from `apps/web/`.
- **Security:** `deleteThread` resolves `userId` server-side and calls the existing `authorizeThread` gate; a non-owner gets a generic `"Not found"` (never reveals another user's thread). No client-supplied userId.
- **Gate (before done):** `npx convex codegen` clean · `npx tsc -p . --noEmit` clean · `npm test` all pass · `npm run build` clean.
- **Tests from task one** (project convention): every task ships runnable tests.
- **Convex test env:** `convex/chat.test.ts` already runs `// @vitest-environment node` and mocks `./agent`; extend that mock rather than reaching the real agent runtime.
- **Commits:** conventional commits; end each message with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

## File Structure

**Modify:**
- `convex/chat.ts` — add `deleteThread` mutation.
- `convex/chat.test.ts` — add `deleteThreadAsync` spy to the `./agent` mock; add delete + authz tests.
- `src/features/chat/ThreadList.tsx` — add `onDelete` prop + per-row kebab menu.
- `src/features/chat/Chat.tsx` — wire `onDelete`, confirm dialog, re-selection.

**Create:**
- `src/test/ThreadList.test.tsx` — delete-affordance test.

---

## Task 1: `deleteThread` backend mutation

**Files:**
- Modify: `convex/chat.ts`, `convex/chat.test.ts`

**Interfaces:**
- Consumes: existing `requireUserId`, `authorizeThread`, `chatAgent` (from `./agent`).
- Produces: `api.chat.deleteThread({ threadId: string }): Promise<null>` — deletes the caller's `chatThreads` row and the agent thread; throws `"Not found"` for a non-owner.

- [ ] **Step 1: Add the `deleteThreadAsync` spy to the test mock**

In `convex/chat.test.ts`, extend the `vi.hoisted` block and the `./agent` mock. Replace the hoisted block + `vi.mock("./agent", …)` (lines 23-45) with:

```ts
const { createThreadMock, continueThreadMock, deleteThreadAsyncMock } = vi.hoisted(() => ({
  createThreadMock: vi.fn(
    async (_ctx: unknown, _args: { userId?: string | null }) => ({
      threadId: `thread_${Math.random().toString(36).slice(2)}`,
    }),
  ),
  continueThreadMock: vi.fn(
    async (
      _ctx: unknown,
      args: { threadId: string; userId?: string | null },
    ) => ({
      thread: {
        threadId: args.threadId,
        streamText: vi.fn(async () => ({
          consumeStream: vi.fn(async () => {}),
        })),
      },
    }),
  ),
  deleteThreadAsyncMock: vi.fn(async (_ctx: unknown, _args: { threadId: string }) => {}),
}));
vi.mock("./agent", () => ({
  chatAgent: {
    createThread: createThreadMock,
    continueThread: continueThreadMock,
    deleteThreadAsync: deleteThreadAsyncMock,
  },
}));
```

- [ ] **Step 2: Write the failing tests** (append to `convex/chat.test.ts`)

```ts
test("deleteThread removes the caller's thread row and calls the agent delete", async () => {
  const t = convexTest(schema, modules);
  const { t: alice, userId: aliceId } = await asNewUser(t, "alice@example.com");

  const threadId = await alice.mutation(api.chat.createThread, {});
  expect(await alice.query(api.chat.listThreads, {})).toHaveLength(1);

  deleteThreadAsyncMock.mockClear();
  await alice.mutation(api.chat.deleteThread, { threadId });

  expect(await alice.query(api.chat.listThreads, {})).toHaveLength(0);
  expect(deleteThreadAsyncMock).toHaveBeenCalledWith(expect.anything(), { threadId });
  // The row is really gone for this user.
  const rows = await t.run((ctx) =>
    ctx.db
      .query("chatThreads")
      .withIndex("by_thread", (q) => q.eq("threadId", threadId))
      .collect(),
  );
  expect(rows).toHaveLength(0);
  void aliceId;
});

test("deleteThread throws 'Not found' for a non-owner and leaves the row intact", async () => {
  const t = convexTest(schema, modules);
  const { t: alice } = await asNewUser(t, "alice@example.com");
  const { t: bob } = await asNewUser(t, "bob@example.com");

  const threadId = await alice.mutation(api.chat.createThread, {});
  deleteThreadAsyncMock.mockClear();

  await expect(bob.mutation(api.chat.deleteThread, { threadId })).rejects.toThrow();
  // Bob's failed attempt neither deleted the row nor reached the agent.
  expect(await alice.query(api.chat.listThreads, {})).toHaveLength(1);
  expect(deleteThreadAsyncMock).not.toHaveBeenCalled();
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `npx vitest run convex/chat.test.ts`
Expected: FAIL — `api.chat.deleteThread` does not exist.

- [ ] **Step 4: Implement `deleteThread`** in `convex/chat.ts`

Add after the `createThread` mutation (after line ~116):

```ts
export const deleteThread = mutation({
  args: { threadId: v.string() },
  handler: async (ctx, { threadId }) => {
    const userId = await requireUserId(ctx);
    // Ownership gate — throws generic "Not found" for a non-owner, never
    // revealing another user's thread.
    await authorizeThread(ctx, threadId, userId);
    // Remove OUR ownership record first, so the thread disappears from the
    // user's list immediately (no orphan visible if the async agent delete
    // lags).
    const row = await ctx.db
      .query("chatThreads")
      .withIndex("by_thread", (q) => q.eq("threadId", threadId))
      .unique();
    if (row !== null) await ctx.db.delete(row._id);
    // Delete the agent component's messages + streams for this thread
    // (batched, safe from a mutation ctx).
    await chatAgent.deleteThreadAsync(ctx, { threadId });
    return null;
  },
});
```

- [ ] **Step 5: Regenerate types + run tests**

Run: `npx convex codegen && npx vitest run convex/chat.test.ts`
Expected: PASS (existing chat tests + the 2 new ones).

- [ ] **Step 6: Commit**

```bash
git add convex/chat.ts convex/chat.test.ts convex/_generated
git commit -m "feat(web): chat.deleteThread mutation — ownership-gated thread delete"
```

---

## Task 2: `ThreadList` kebab menu + `onDelete`

**Files:**
- Modify: `src/features/chat/ThreadList.tsx`
- Create: `src/test/ThreadList.test.tsx`

**Interfaces:**
- Consumes: shadcn `DropdownMenu`.
- Produces: `ThreadList` gains a required-ish `onDelete: (threadId: string) => void` prop; each row shows a `⋯` trigger (aria-label "Conversation options") that opens a menu whose Delete item calls `onDelete(threadId)`.

- [ ] **Step 1: Write the failing test**

```tsx
// src/test/ThreadList.test.tsx
import { render, screen, fireEvent } from "@testing-library/react";
import { vi, expect, test } from "vitest";
import ThreadList, { type ThreadRow } from "@/features/chat/ThreadList";

const threads: ThreadRow[] = [
  { _id: "1", threadId: "t1", title: "Q3 planning", createdAt: 1 },
  { _id: "2", threadId: "t2", title: "Roadmap", createdAt: 2 },
];

function setup(onDelete = vi.fn()) {
  render(
    <ThreadList
      threads={threads}
      activeThreadId="t1"
      onSelect={vi.fn()}
      onNewChat={vi.fn()}
      open
      onClose={vi.fn()}
      onDelete={onDelete}
    />,
  );
  return onDelete;
}

test("opening a row's kebab menu and clicking Delete calls onDelete with the threadId", async () => {
  const onDelete = setup();
  // One options trigger per row.
  const triggers = screen.getAllByRole("button", { name: /conversation options/i });
  expect(triggers).toHaveLength(2);
  fireEvent.click(triggers[0]);
  const del = await screen.findByRole("menuitem", { name: /delete/i });
  fireEvent.click(del);
  expect(onDelete).toHaveBeenCalledWith("t1");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run ThreadList`
Expected: FAIL — `onDelete` prop / kebab not present.

- [ ] **Step 3: Implement the kebab menu** in `src/features/chat/ThreadList.tsx`

3a. Update the imports (line 1):

```tsx
import { Plus, X, PanelLeftClose, MoreHorizontal, Trash2 } from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
```

3b. Add `onDelete` to the props type and destructuring:

```tsx
export default function ThreadList({
  threads,
  activeThreadId,
  onSelect,
  onNewChat,
  open,
  desktopHidden = false,
  onClose,
  onCollapse,
  onDelete,
}: {
  threads: ThreadRow[];
  activeThreadId: string | null;
  onSelect: (threadId: string) => void;
  onNewChat: () => void;
  open: boolean;
  desktopHidden?: boolean;
  onClose: () => void;
  onCollapse?: () => void;
  onDelete: (threadId: string) => void;
}) {
```

3c. Replace the `<li>` body (lines 90-115, the `<li key={t._id}>…</li>`) so the row button and the kebab are siblings inside a `group` wrapper. The kebab is hidden until hover / active / menu-open (and always visible on touch via `focus-within` is unreliable — we keep it simple: show on `group-hover` and when the row is active):

```tsx
                <li key={t._id} className="group relative">
                  <button
                    type="button"
                    onClick={() => onSelect(t.threadId)}
                    aria-current={active || undefined}
                    className={cn(
                      "relative flex w-full flex-col gap-0.5 rounded-lg py-2 pl-3 pr-9 text-left transition-colors",
                      active ? "bg-accent/70" : "hover:bg-accent/50",
                    )}
                  >
                    {active && (
                      <span className="absolute inset-y-2 left-0 w-[3px] rounded-r bg-primary" />
                    )}
                    <span
                      className={cn(
                        "truncate text-sm font-medium",
                        active ? "text-accent-foreground" : "text-foreground",
                      )}
                    >
                      {t.title ?? "New conversation"}
                    </span>
                    <span className="truncate text-xs text-muted-foreground">
                      {relativeDay(t.createdAt)}
                    </span>
                  </button>
                  <DropdownMenu>
                    <DropdownMenuTrigger
                      aria-label="Conversation options"
                      className={cn(
                        "absolute right-1.5 top-1/2 grid h-7 w-7 -translate-y-1/2 place-items-center rounded-md text-muted-foreground outline-none transition hover:bg-accent hover:text-foreground focus-visible:opacity-100 data-[state=open]:opacity-100 data-[state=open]:bg-accent",
                        "opacity-0 group-hover:opacity-100",
                        active && "opacity-100",
                      )}
                    >
                      <MoreHorizontal className="h-4 w-4" />
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end" className="w-40">
                      <DropdownMenuItem
                        className="text-destructive focus:text-destructive"
                        onClick={() => onDelete(t.threadId)}
                      >
                        <Trash2 className="h-4 w-4" />
                        Delete
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </li>
```

> `DropdownMenuItem` in this codebase has no `variant` prop; the destructive tint comes from `className="text-destructive focus:text-destructive"` above.

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run ThreadList`
Expected: PASS. (If the menu renders in a portal, `findByRole("menuitem")` still finds it; Radix renders into the body.)

- [ ] **Step 5: Commit**

```bash
git add src/features/chat/ThreadList.tsx src/test/ThreadList.test.tsx
git commit -m "feat(web): per-conversation kebab menu with Delete in the chat rail"
```

---

## Task 3: Wire confirm + delete into `Chat`

**Files:**
- Modify: `src/features/chat/Chat.tsx`, `src/test/Chat.test.tsx`

**Interfaces:**
- Consumes: `api.chat.deleteThread` (Task 1), `ThreadList.onDelete` (Task 2).
- Produces: confirm dialog + delete; on deleting the active thread, re-selects the most recent remaining thread (or empty state).

- [ ] **Step 1: Write the failing test** (append to `src/test/Chat.test.tsx`)

The Chat test file mocks `useMutation` generically (`useMutation: () => vi.fn(() => Promise.resolve())`). To assert the delete call, capture it. Replace the `useMutation` line in the `convex/react` mock (currently `useMutation: () => vi.fn(() => Promise.resolve()),`) with a routed version, and add the top-level `deleteThreadMock`:

```tsx
// add near the other top-level consts (e.g. after `const sendMessage = …`)
const deleteThreadMock = vi.fn(() => Promise.resolve());
```

```tsx
// inside vi.mock("convex/react", …), replace the useMutation entry:
  useMutation: (m?: Parameters<typeof getFunctionName>[0]) => {
    if (m && getFunctionName(m) === getFunctionName(api.chat.deleteThread))
      return deleteThreadMock;
    return vi.fn(() => Promise.resolve());
  },
```

Then the test:

```tsx
test("deleting a conversation confirms then calls deleteThread", async () => {
  mockedUseUIMessages.mockReturnValue(baseMessages as any);
  deleteThreadMock.mockClear();
  renderChat();

  // Open the active row's kebab (the mocked listThreads returns thread "thread1").
  const trigger = screen.getAllByRole("button", { name: /conversation options/i })[0];
  fireEvent.click(trigger);
  fireEvent.click(await screen.findByRole("menuitem", { name: /delete/i }));

  // Confirm dialog appears; confirm it.
  await screen.findByText(/delete conversation/i);
  fireEvent.click(screen.getByRole("button", { name: /^delete$/i }));

  await waitFor(() =>
    expect(deleteThreadMock).toHaveBeenCalledWith({ threadId: "thread1" }),
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/test/Chat.test.tsx`
Expected: FAIL — no kebab/confirm wired in Chat yet.

- [ ] **Step 3: Implement in `src/features/chat/Chat.tsx`**

3a. Add the mutation next to the others (after `const createThread = …`, ~line 47):

```tsx
  const deleteThread = useMutation(api.chat.deleteThread);
```

3b. Add pending-delete state near the other rail state (after `railHidden`, ~line 74):

```tsx
  // The threadId awaiting delete confirmation.
  const [pendingDelete, setPendingDelete] = useState<string | null>(null);
```

3c. Add the delete handler (near `handleNewChat`, ~line 143):

```tsx
  async function confirmDelete() {
    const id = pendingDelete;
    setPendingDelete(null);
    if (!id) return;
    try {
      await deleteThread({ threadId: id });
      if (id === threadId) {
        // Re-select the most recent remaining thread (threads is desc-ordered),
        // or fall to the empty state when none remain.
        const next = threads.find((t) => t.threadId !== id);
        setThreadId(next ? next.threadId : null);
      }
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to delete conversation");
    }
  }
```

3d. Pass `onDelete` to `ThreadList` (both the JSX usage near line 239). Add the prop:

```tsx
      <ThreadList
        threads={threads}
        activeThreadId={threadId}
        onSelect={selectThread}
        onNewChat={() => void handleNewChat()}
        open={railOpen}
        desktopHidden={railHidden}
        onClose={() => setRailOpen(false)}
        onCollapse={toggleRail}
        onDelete={(id) => setPendingDelete(id)}
      />
```

3e. Render the confirm dialog. Add it right before the closing `</div>` where the `DuplicateDialog` is rendered (place it as a sibling, just after the `DuplicateDialog` block near the end of the return):

```tsx
      <Dialog
        open={pendingDelete !== null}
        onOpenChange={(open) => {
          if (!open) setPendingDelete(null);
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete conversation</DialogTitle>
            <DialogDescription>
              This conversation and its messages will be permanently deleted.
              This can&apos;t be undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setPendingDelete(null)}>
              Cancel
            </Button>
            <Button variant="destructive" onClick={() => void confirmDelete()}>
              Delete
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
```

3f. Add the imports for the dialog + button primitives (top of file, with the other imports):

```tsx
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx vitest run src/test/Chat.test.tsx`
Expected: PASS (all Chat tests including the new delete test).

> If `Button` doesn't support `variant="destructive"` in this codebase, use `variant="outline" className="text-destructive"` for the Delete button; the test matches on the button name "Delete", not its variant.

- [ ] **Step 5: Typecheck + commit**

```bash
npx tsc -p . --noEmit
git add src/features/chat/Chat.tsx src/test/Chat.test.tsx
git commit -m "feat(web): confirm + delete conversation, re-select most recent remaining"
```

---

## Task 4: Gate + STATUS.md

**Files:**
- Modify: `STATUS.md`

- [ ] **Step 1: Full gate**

Run (from `apps/web`): `npx convex codegen && npx tsc -p . --noEmit && npm test && npm run build`
Expected: all clean/green.

- [ ] **Step 2: Update STATUS.md**

Add a **C6** row to the web slices table (`| C6 | Delete chat conversation | ✅ code-complete (browser smoke pending) | …`), update the "Now (web)" line, the platform table's Web cell, and "Last updated" (2026-07-13). Keep it honest: browser smoke pending until run.

- [ ] **Step 3: Browser smoke (manual, after gate green)**

With `npx convex dev` running + signed in: create 2–3 conversations; delete a non-active one (it vanishes, others stay); delete the active one (jumps to the most recent remaining; empty state when none remain); reload and confirm the deleted thread's messages are gone; confirm a Cancel leaves everything intact.

- [ ] **Step 4: Commit**

```bash
git add STATUS.md
git commit -m "docs(status): C6 — delete chat conversation"
```

---

## Self-Review

**Spec coverage:**
- Backend `deleteThread` (gate → delete row → `deleteThreadAsync`) → Task 1. ✅
- Kebab menu + Delete item → Task 2. ✅
- Confirm dialog + re-selection of most recent remaining → Task 3. ✅
- Authorization (non-owner "Not found", no agent call) → Task 1 test. ✅
- Gate + STATUS → Task 4. ✅

**Placeholder scan:** every code step has full code. The two "if the shadcn version differs" notes are concrete fallbacks (exact className given), not placeholders.

**Type consistency:** `deleteThread({ threadId })` signature identical across backend (Task 1), the Chat mutation call (Task 3), and both tests; `onDelete: (threadId: string) => void` identical in `ThreadList` props (Task 2) and the `Chat` wiring (Task 3); dialog primitives (`Dialog`/`DialogContent`/…/`DialogFooter`, `Button`) match the exports already used by `DuplicateDialog`.
