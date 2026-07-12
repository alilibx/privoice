# C5 — Web Chat UX + Document De-dup + List-Documents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the chat message list auto-follow the conversation (stick-to-bottom), guard against uploading byte-identical duplicate documents, and let the assistant enumerate the user's full document inventory on request.

**Architecture:** Three independent slices in `apps/web`. (1) A pure `useStickToBottom` DOM hook drives the chat scroll container. (2) A client-side SHA-256 pre-flight compares an upload against the already-loaded document list; a shared `DuplicateDialog` confirms before creating a second copy, with "Use existing" reusing the current document (in chat: pinning it). (3) A userId-scoped `listDocuments` agent tool backed by an internal query returns the whole document inventory.

**Tech Stack:** React 18 + Vite, TypeScript, Convex (queries/mutations/internalQuery + `@convex-dev/agent` tools), shadcn/ui (Dialog, Button), Vitest + Testing Library, Web Crypto (`crypto.subtle`).

## Global Constraints

- **Directory:** all work under `apps/web/`. Run commands from `apps/web/` unless noted.
- **Privacy:** web/cloud only; do not touch the on-device mobile invariant. `contentHash` derives from the user's own file and stays in their per-user row.
- **Security:** the `listDocuments` tool takes NO `userId` in its input schema; it resolves the caller from `ctx.userId` via the existing `requireCallerUserId(ctx)` helper and fails closed if absent. Its backing query is an `internalQuery` (client-unreachable).
- **Gate (run before declaring done):** `npx convex codegen` clean · `npx tsc -p . --noEmit` clean · `npm test` all pass · `npm run build` clean.
- **Tests from task one** (project convention): every task ships runnable tests; no gating test execution behind deploy.
- **Convex test env:** suites that store blobs / exercise `convex-test` use `// @vitest-environment node` at the top of the file (jsdom's Blob lacks `arrayBuffer()`); component/hook suites stay on the default jsdom.
- **Commits:** conventional commits; end each message with the `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer.

---

## File Structure

**Create:**
- `src/features/chat/use-stick-to-bottom.ts` — pure scroll-follow hook.
- `src/test/use-stick-to-bottom.test.ts` — hook unit tests.
- `src/features/documents/content-hash.ts` — `hashFile(file)` / `sha256Hex(buf)`.
- `src/test/content-hash.test.ts` — hash unit tests.
- `src/features/documents/DuplicateDialog.tsx` — shared confirm dialog.
- `src/test/DuplicateDialog.test.tsx` — dialog component tests.

**Modify:**
- `convex/schema.ts` — add optional `contentHash` to `documents`.
- `convex/documents.ts` — `create` accepts+stores `contentHash`; add `listForUser` internalQuery.
- `convex/documents.test.ts` — cover `contentHash` persistence + `listForUser`.
- `convex/tools.ts` — add `listDocuments` tool.
- `convex/tools.test.ts` — cover `listDocuments` userId scoping.
- `convex/agent.ts` — register `listDocuments` + instruction sentence.
- `src/features/chat/Chat.tsx` — wire scroll hook + jump pill + attach de-dup.
- `src/test/Chat.test.tsx` — scroll-on-send + attach-dedup coverage.
- `src/features/documents/DocumentsList.tsx` — upload de-dup pre-flight.
- `src/features/documents/DocumentCard.tsx` — add `contentHash?` to `DocumentRow`.

---

## Task 1: `useStickToBottom` hook

**Files:**
- Create: `src/features/chat/use-stick-to-bottom.ts`
- Test: `src/test/use-stick-to-bottom.test.ts`

**Interfaces:**
- Produces: `useStickToBottom<T extends HTMLElement>()` returning
  `{ ref: React.RefObject<T | null>, atBottom: boolean, onScroll: () => void, scrollToBottom: (behavior?: ScrollBehavior) => void, stick: () => void }`.
  - `atBottom` reflects whether the container was within 64px of the bottom at the last scroll event (drives the "jump to latest" pill).
  - `scrollToBottom` scrolls the container to `scrollHeight` and marks at-bottom.
  - `stick` scrolls to bottom **only if** the container was at-bottom as of the last scroll (uses a ref mirror so appended content doesn't defeat the check, and to avoid a stale closure).

- [ ] **Step 1: Write the failing test**

```ts
// src/test/use-stick-to-bottom.test.ts
import { renderHook, act } from "@testing-library/react";
import { vi, expect, test } from "vitest";
import { useStickToBottom } from "@/features/chat/use-stick-to-bottom";

// jsdom does no layout, so fake an element exposing the scroll metrics the
// hook reads plus a spyable scrollTo.
function fakeEl(over: Partial<Record<"scrollHeight" | "clientHeight" | "scrollTop", number>> = {}) {
  return {
    scrollHeight: 1000,
    clientHeight: 300,
    scrollTop: 700, // 1000 - 700 - 300 = 0 → at bottom
    scrollTo: vi.fn(),
    ...over,
  };
}

test("atBottom is true within threshold, false when scrolled up", () => {
  const { result } = renderHook(() => useStickToBottom<HTMLDivElement>());
  const el = fakeEl();
  // @ts-expect-error assigning a fake element to the ref for the test
  result.current.ref.current = el;

  act(() => result.current.onScroll());
  expect(result.current.atBottom).toBe(true);

  el.scrollTop = 0; // 1000 - 0 - 300 = 700 > 64 → not at bottom
  act(() => result.current.onScroll());
  expect(result.current.atBottom).toBe(false);
});

test("stick scrolls only when at bottom; scrollToBottom always scrolls", () => {
  const { result } = renderHook(() => useStickToBottom<HTMLDivElement>());
  const el = fakeEl();
  // @ts-expect-error fake element
  result.current.ref.current = el;

  act(() => result.current.onScroll()); // at bottom
  act(() => result.current.stick());
  expect(el.scrollTo).toHaveBeenCalledTimes(1);

  el.scrollTop = 0;
  act(() => result.current.onScroll()); // scrolled up
  el.scrollTo.mockClear();
  act(() => result.current.stick());
  expect(el.scrollTo).not.toHaveBeenCalled();

  act(() => result.current.scrollToBottom("smooth"));
  expect(el.scrollTo).toHaveBeenCalledWith({ top: 1000, behavior: "smooth" });
  expect(result.current.atBottom).toBe(true);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- use-stick-to-bottom`
Expected: FAIL — cannot resolve `@/features/chat/use-stick-to-bottom`.

- [ ] **Step 3: Write minimal implementation**

```ts
// src/features/chat/use-stick-to-bottom.ts
import { useCallback, useRef, useState } from "react";

// How close (px) to the bottom still counts as "at the bottom".
const THRESHOLD = 64;

/**
 * Stick-to-bottom scroll behavior for a scrollable container.
 *
 * Attach `ref` to the scroll element and `onScroll` to its onScroll. Call
 * `stick()` whenever content changes to follow the stream — it only scrolls
 * if the user was already at the bottom (tracked from the last scroll event
 * via a ref mirror, so newly appended content can't flip the check first, and
 * the callback never reads a stale value). `scrollToBottom()` forces a scroll
 * (used for the user's own send and the "jump to latest" pill).
 */
export function useStickToBottom<T extends HTMLElement>() {
  const ref = useRef<T | null>(null);
  const [atBottom, setAtBottom] = useState(true);
  const atBottomRef = useRef(true);

  const set = useCallback((v: boolean) => {
    atBottomRef.current = v;
    setAtBottom(v);
  }, []);

  const computeAtBottom = useCallback(() => {
    const el = ref.current;
    if (!el) return true;
    return el.scrollHeight - el.scrollTop - el.clientHeight <= THRESHOLD;
  }, []);

  const onScroll = useCallback(() => {
    set(computeAtBottom());
  }, [computeAtBottom, set]);

  const scrollToBottom = useCallback(
    (behavior: ScrollBehavior = "auto") => {
      const el = ref.current;
      if (!el) return;
      el.scrollTo({ top: el.scrollHeight, behavior });
      set(true);
    },
    [set],
  );

  const stick = useCallback(() => {
    if (atBottomRef.current) scrollToBottom("auto");
  }, [scrollToBottom]);

  return { ref, atBottom, onScroll, scrollToBottom, stick };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- use-stick-to-bottom`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/features/chat/use-stick-to-bottom.ts src/test/use-stick-to-bottom.test.ts
git commit -m "feat(web): useStickToBottom scroll-follow hook"
```

---

## Task 2: Wire scroll-follow into Chat

**Files:**
- Modify: `src/features/chat/Chat.tsx`
- Test: `src/test/Chat.test.tsx`

**Interfaces:**
- Consumes: `useStickToBottom` from Task 1.
- Produces: no new exports; observable behavior — the messages container follows the stream and a "Jump to latest" button appears when scrolled up.

- [ ] **Step 1: Write the failing test** (append to `src/test/Chat.test.tsx`)

Add near the top of the file, after the existing imports, a scroll stub (jsdom doesn't implement `Element.prototype.scrollTo`), then a test. Place the `beforeAll` and test alongside the existing suite:

```tsx
import { beforeAll } from "vitest";

beforeAll(() => {
  // jsdom has no layout / scrollTo; stub so the hook's scroll calls are spyable.
  Element.prototype.scrollTo = vi.fn() as unknown as typeof Element.prototype.scrollTo;
});

test("scrolls to bottom after sending a message", async () => {
  mockedUseUIMessages.mockReturnValue(baseMessages as never);
  const scrollTo = vi.spyOn(Element.prototype, "scrollTo");
  renderChat();

  const box = screen.getByPlaceholderText(/Ask about your documents/i);
  fireEvent.change(box, { target: { value: "Hello there" } });
  fireEvent.keyDown(box, { key: "Enter" });

  await waitFor(() => expect(scrollTo).toHaveBeenCalled());
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- Chat`
Expected: FAIL — `scrollTo` not called (the container isn't wired yet).

- [ ] **Step 3: Implement the wiring** in `src/features/chat/Chat.tsx`

3a. Add the import (with the other feature imports near line 19):

```tsx
import { useStickToBottom } from "@/features/chat/use-stick-to-bottom";
```

3b. Add `ArrowDown` to the lucide import on line 6:

```tsx
import { Menu, MessagesSquare, PanelLeft, ArrowDown } from "lucide-react";
```

3c. Inside `Chat()`, after the `railHidden` state (around line 74), add the hook:

```tsx
  const {
    ref: scrollRef,
    atBottom,
    onScroll,
    scrollToBottom,
    stick,
  } = useStickToBottom<HTMLDivElement>();
```

3d. Follow the stream: add an effect after the existing `pending`-reconcile effects (after the effect ending near line 116):

```tsx
  // Follow the conversation as it grows/streams — but only if the user is
  // already at the bottom (stick() gates on that). handleSend force-scrolls
  // separately, so a send always lands at the latest.
  useEffect(() => {
    stick();
  }, [messages, pending, stick]);
```

3e. Reset to bottom on thread switch — extend the existing `threadId` reset effect (the one clearing pending/attachments around lines 117-121) by appending a scroll:

```tsx
  useEffect(() => {
    setPending([]);
    setPendingAttachments([]);
    setSentAttachments([]);
    scrollToBottom("auto");
  }, [threadId, scrollToBottom]);
```

3f. Force-scroll on the user's own send. In `handleSend`, right after the optimistic `setPending((p) => [...p, { text: trimmed, attachments: atts }]);` line (~160), add:

```tsx
    // The user's own send always jumps to the latest, even if they'd scrolled
    // up. rAF lets the optimistic bubble paint first so scrollHeight is final.
    requestAnimationFrame(() => scrollToBottom("auto"));
```

3g. Attach the ref + onScroll to the messages container (line 325). Replace:

```tsx
        {/* Messages */}
        <div className="flex-1 overflow-y-auto">
```

with:

```tsx
        {/* Messages */}
        <div ref={scrollRef} onScroll={onScroll} className="flex-1 overflow-y-auto">
```

3h. Add the "Jump to latest" pill. Immediately AFTER that messages `</div>` closes (after line 367, before the `{/* Composer */}` comment), inside the `chat-canvas` relative wrapper, add:

```tsx
        {!atBottom && !isEmpty && (
          <button
            type="button"
            onClick={() => scrollToBottom("smooth")}
            className="absolute bottom-28 left-1/2 z-10 -translate-x-1/2 inline-flex items-center gap-1.5 rounded-full border bg-card/90 px-3 py-1.5 text-xs font-medium text-foreground shadow-md backdrop-blur transition hover:border-primary/40"
          >
            Jump to latest
            <ArrowDown className="h-3.5 w-3.5" />
          </button>
        )}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npm test -- Chat`
Expected: PASS (existing Chat tests + the new scroll-on-send test).

- [ ] **Step 5: Typecheck + commit**

```bash
npx tsc -p . --noEmit
git add src/features/chat/Chat.tsx src/test/Chat.test.tsx
git commit -m "feat(web): chat message list follows the stream + jump-to-latest pill"
```

---

## Task 3: De-dup foundations — `contentHash` column + `create` arg + hash helper

**Files:**
- Modify: `convex/schema.ts`, `convex/documents.ts`
- Create: `src/features/documents/content-hash.ts`, `src/test/content-hash.test.ts`
- Test: `convex/documents.test.ts`

**Interfaces:**
- Produces (client): `hashFile(file: File): Promise<string>` and `sha256Hex(buf: ArrayBuffer): Promise<string>` — lowercase hex SHA-256.
- Produces (server): `documents.create` now accepts optional `contentHash: string` and stores it; `documents` rows carry optional `contentHash`.

- [ ] **Step 1: Write the failing hash test**

```ts
// src/test/content-hash.test.ts
import { expect, test } from "vitest";
import { sha256Hex, hashFile } from "@/features/documents/content-hash";

test("sha256Hex matches known vectors", async () => {
  const empty = await sha256Hex(new Uint8Array().buffer);
  expect(empty).toBe(
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  );
  const abc = await sha256Hex(new TextEncoder().encode("abc").buffer);
  expect(abc).toBe(
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  );
});

test("hashFile hashes the file's bytes", async () => {
  const file = new File([new TextEncoder().encode("abc")], "a.txt", {
    type: "text/plain",
  });
  expect(await hashFile(file)).toBe(
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- content-hash`
Expected: FAIL — cannot resolve `@/features/documents/content-hash`.

- [ ] **Step 3: Implement the hash helper**

```ts
// src/features/documents/content-hash.ts

/** Lowercase hex SHA-256 of the given bytes (Web Crypto, browser-native). */
export async function sha256Hex(bytes: ArrayBuffer): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** SHA-256 (hex) of a File's contents — used to detect exact duplicates. */
export async function hashFile(file: File): Promise<string> {
  return sha256Hex(await file.arrayBuffer());
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- content-hash`
Expected: PASS (2 tests).

- [ ] **Step 5: Add the schema column**

In `convex/schema.ts`, add to the `documents` table definition (after `chunkCount`, before `createdAt`):

```ts
    chunkCount: v.number(),
    // SHA-256 (hex) of the uploaded bytes, set at create time. Optional so
    // pre-existing rows stay valid; used only to detect exact duplicates
    // (same filename + same hash) at upload — never a uniqueness constraint.
    contentHash: v.optional(v.string()),
    createdAt: v.number(),
```

- [ ] **Step 6: Thread `contentHash` through `create`**

In `convex/documents.ts`, update the `create` mutation:

```ts
export const create = mutation({
  args: {
    storageId: v.id("_storage"),
    filename: v.string(),
    mimeType: v.string(),
    sizeBytes: v.number(),
    contentHash: v.optional(v.string()),
  },
  handler: async (ctx, { storageId, filename, mimeType, sizeBytes, contentHash }) => {
    const userId = await requireUserId(ctx);
    if (sizeBytes > MAX_BYTES) throw new ConvexError("File exceeds 10 MB limit");
    const ext = filename.split(".").pop()?.toLowerCase() ?? "";
    const kind = KIND_BY_EXT[ext];
    if (!kind) throw new ConvexError("Unsupported file type");
    const documentId = await ctx.db.insert("documents", {
      userId, storageId, filename, mimeType, kind, sizeBytes, contentHash,
      status: "parsing", chunkCount: 0, createdAt: Date.now(),
    });
    await ctx.scheduler.runAfter(0, internal.ingest.ingestDocument, { documentId });
    return documentId;
  },
});
```

- [ ] **Step 7: Regenerate Convex types**

Run: `npx convex codegen`
Expected: no errors; `_generated` updated for the new arg/field.

- [ ] **Step 8: Write the failing backend test** (append to `convex/documents.test.ts`)

```ts
test("create persists contentHash when provided", async () => {
  vi.useFakeTimers();
  try {
    const t = convexTest(schema, modules);
    const { t: alice, userId } = await asNewUser(t, "hash@x.com");
    const storageId = await alice.run(async (ctx) =>
      ctx.storage.store(new Blob([new Uint8Array([1, 2, 3])])),
    );
    const id = await alice.mutation(api.documents.create, {
      storageId,
      filename: "a.pdf",
      mimeType: "application/pdf",
      sizeBytes: 3,
      contentHash: "deadbeef",
    });
    const doc = await t.run((ctx) => ctx.db.get(id));
    expect(doc?.contentHash).toBe("deadbeef");
    expect(doc?.userId).toBe(userId);
  } finally {
    vi.useRealTimers();
  }
});
```

- [ ] **Step 9: Run the backend test**

Run: `npm test -- documents`
Expected: PASS (existing + new). If `asNewUser`/`modules` import differs, reuse the helpers already defined at the top of `documents.test.ts` (do not redefine them).

- [ ] **Step 10: Commit**

```bash
git add convex/schema.ts convex/documents.ts convex/_generated \
  src/features/documents/content-hash.ts src/test/content-hash.test.ts convex/documents.test.ts
git commit -m "feat(web): store contentHash on documents + client sha256 helper"
```

---

## Task 4: `DuplicateDialog` + Documents-page de-dup pre-flight

**Files:**
- Create: `src/features/documents/DuplicateDialog.tsx`, `src/test/DuplicateDialog.test.tsx`
- Modify: `src/features/documents/DocumentsList.tsx`, `src/features/documents/DocumentCard.tsx`

**Interfaces:**
- Consumes: `hashFile` (Task 3), `contentHash` field on document rows (Task 3).
- Produces: `DuplicateDialog` component with props
  `{ open: boolean; filename: string; onOpenChange: (open: boolean) => void; onUseExisting: () => void; onUploadAnyway: () => void }`.
- Produces: `DocumentRow` type gains `contentHash?: string`.

- [ ] **Step 1: Write the failing dialog test**

```tsx
// src/test/DuplicateDialog.test.tsx
import { render, screen, fireEvent } from "@testing-library/react";
import { vi, expect, test } from "vitest";
import DuplicateDialog from "@/features/documents/DuplicateDialog";

test("shows the filename and fires the right callbacks", () => {
  const onUseExisting = vi.fn();
  const onUploadAnyway = vi.fn();
  render(
    <DuplicateDialog
      open
      filename="report.pdf"
      onOpenChange={() => {}}
      onUseExisting={onUseExisting}
      onUploadAnyway={onUploadAnyway}
    />,
  );
  expect(screen.getByText("report.pdf")).toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: /use existing/i }));
  expect(onUseExisting).toHaveBeenCalledTimes(1);
  fireEvent.click(screen.getByRole("button", { name: /upload anyway/i }));
  expect(onUploadAnyway).toHaveBeenCalledTimes(1);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- DuplicateDialog`
Expected: FAIL — cannot resolve `@/features/documents/DuplicateDialog`.

- [ ] **Step 3: Implement `DuplicateDialog`**

```tsx
// src/features/documents/DuplicateDialog.tsx
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";

export default function DuplicateDialog({
  open,
  filename,
  onOpenChange,
  onUseExisting,
  onUploadAnyway,
}: {
  open: boolean;
  filename: string;
  onOpenChange: (open: boolean) => void;
  onUseExisting: () => void;
  onUploadAnyway: () => void;
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>You already have this file</DialogTitle>
          <DialogDescription>
            <span className="font-medium text-foreground">{filename}</span> is
            already in your documents and hasn&apos;t changed. Upload another
            copy?
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" onClick={onUploadAnyway}>
            Upload anyway
          </Button>
          <Button onClick={onUseExisting}>Use existing</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- DuplicateDialog`
Expected: PASS.

- [ ] **Step 5: Add `contentHash` to `DocumentRow`**

In `src/features/documents/DocumentCard.tsx`, find the `DocumentRow` type and add the field (it currently lists `_id`, `filename`, `kind`, `status`, `sizeBytes`, `createdAt`, etc.):

```tsx
export type DocumentRow = {
  // ...existing fields...
  contentHash?: string;
};
```

(If `DocumentRow` is declared elsewhere, add `contentHash?: string;` there. Do not remove existing fields.)

- [ ] **Step 6: Write the failing DocumentsList de-dup test**

The existing `src/test/Documents.test.tsx` has a **module-scope** `vi.mock("convex/react")` whose `useQuery` returns a fixed array for every query and whose `useMutation` returns a generic `vi.fn()`. Rework that mock so (a) one doc carries a `contentHash`, and (b) `useMutation` distinguishes `create` so the test can assert it isn't called. Replace the file's mock block + add the new test. The full file becomes:

```tsx
// src/test/Documents.test.tsx
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { vi, expect, test } from "vitest";
import { getFunctionName } from "convex/server";
import DocumentsList from "@/features/documents/DocumentsList";
import { api } from "../../convex/_generated/api";

vi.mock("@/features/documents/content-hash", () => ({
  hashFile: vi.fn(async () => "hash-abc"),
  sha256Hex: vi.fn(async () => "hash-abc"),
}));

const createMock = vi.fn(async () => "newdoc");

vi.mock("convex/react", () => ({
  useQuery: (q: Parameters<typeof getFunctionName>[0]) => {
    if (getFunctionName(q) === getFunctionName(api.documents.list))
      return [
        {
          _id: "1",
          filename: "report.pdf",
          kind: "pdf",
          status: "ready",
          chunkCount: 12,
          sizeBytes: 10,
          contentHash: "hash-abc",
        },
        { _id: "2", filename: "data.xlsx", kind: "xlsx", status: "parsing", chunkCount: 0, sizeBytes: 5 },
      ];
    return [];
  },
  useMutation: (m: Parameters<typeof getFunctionName>[0]) => {
    if (getFunctionName(m) === getFunctionName(api.documents.create)) return createMock;
    if (getFunctionName(m) === getFunctionName(api.documents.generateUploadUrl))
      return vi.fn(async () => "https://upload");
    return vi.fn();
  },
}));

test("lists documents with status", () => {
  render(<DocumentsList />);
  expect(screen.getByText("report.pdf")).toBeInTheDocument();
  expect(screen.getByText("data.xlsx")).toBeInTheDocument();
  expect(screen.getByText(/ready/i)).toBeInTheDocument();
  expect(screen.getByText(/parsing/i)).toBeInTheDocument();
  expect(screen.getByLabelText(/upload/i)).toBeInTheDocument();
});

test("same name + same hash opens the duplicate dialog; Use existing skips create", async () => {
  createMock.mockClear();
  render(<DocumentsList />);

  const input = document.querySelector('input[type="file"]') as HTMLInputElement;
  const file = new File([new Uint8Array([1])], "report.pdf", { type: "application/pdf" });
  fireEvent.change(input, { target: { files: [file] } });

  await screen.findByText("You already have this file");
  fireEvent.click(screen.getByRole("button", { name: /use existing/i }));
  await waitFor(() =>
    expect(screen.queryByText("You already have this file")).not.toBeInTheDocument(),
  );
  expect(createMock).not.toHaveBeenCalled();
});
```

> Note the dialog asserts on the heading "You already have this file" rather than "report.pdf" — the latter also appears in the document grid, so it isn't unique.

- [ ] **Step 7: Run test to verify it fails**

Run: `npm test -- Documents`
Expected: FAIL — no dialog appears (de-dup not wired).

- [ ] **Step 8: Wire de-dup into `DocumentsList`**

Replace the body of `src/features/documents/DocumentsList.tsx` with:

```tsx
import { useState } from "react";
import { useQuery, useMutation } from "convex/react";
import { toast } from "sonner";
import { api } from "../../../convex/_generated/api";
import type { Id } from "../../../convex/_generated/dataModel";
import PageHeader from "@/components/layout/PageHeader";
import DocumentCard, { type DocumentRow } from "@/features/documents/DocumentCard";
import UploadDropzone from "@/features/documents/UploadDropzone";
import DuplicateDialog from "@/features/documents/DuplicateDialog";
import { hashFile } from "@/features/documents/content-hash";

export default function DocumentsList() {
  const docs = (useQuery(api.documents.list) ?? []) as DocumentRow[];
  const generateUploadUrl = useMutation(api.documents.generateUploadUrl);
  const create = useMutation(api.documents.create);
  const remove = useMutation(api.documents.remove);
  const [busy, setBusy] = useState(false);
  // The file awaiting a duplicate decision, plus its computed hash.
  const [dup, setDup] = useState<{ file: File; hash: string } | null>(null);

  // Byte-identical + same-name copy already present (ready or still parsing)?
  function findDuplicate(filename: string, hash: string): DocumentRow | undefined {
    return docs.find(
      (d) =>
        d.filename === filename &&
        d.contentHash === hash &&
        (d.status === "ready" || d.status === "parsing"),
    );
  }

  async function doUpload(file: File, contentHash: string) {
    setBusy(true);
    try {
      const url = await generateUploadUrl();
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": file.type },
        body: file,
      });
      const { storageId } = await res.json();
      await create({
        storageId,
        filename: file.name,
        mimeType: file.type,
        sizeBytes: file.size,
        contentHash,
      });
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Upload failed");
    } finally {
      setBusy(false);
    }
  }

  async function upload(file: File) {
    const hash = await hashFile(file);
    if (findDuplicate(file.name, hash)) {
      setDup({ file, hash });
      return;
    }
    await doUpload(file, hash);
  }

  async function handleDelete(id: string) {
    try {
      await remove({ id: id as Id<"documents"> });
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to delete document");
    }
  }

  return (
    <div className="flex h-full flex-col">
      <PageHeader title="Documents" />
      <div className="flex-1 overflow-y-auto">
        <div className="mx-auto max-w-3xl p-4 sm:p-6">
          <UploadDropzone onFile={(f) => void upload(f)} busy={busy} />
          {docs.length === 0 ? (
            <p className="mt-16 text-center text-muted-foreground">
              No documents yet
            </p>
          ) : (
            <div className="mt-6 grid grid-cols-1 gap-3 sm:grid-cols-2">
              {docs.map((d) => (
                <DocumentCard
                  key={d._id}
                  doc={d}
                  onDelete={(id) => void handleDelete(id)}
                />
              ))}
            </div>
          )}
        </div>
      </div>
      <DuplicateDialog
        open={dup !== null}
        filename={dup?.file.name ?? ""}
        onOpenChange={(open) => {
          if (!open) setDup(null);
        }}
        onUseExisting={() => {
          setDup(null);
          toast.success("Using your existing copy");
        }}
        onUploadAnyway={() => {
          const pending = dup;
          setDup(null);
          if (pending) void doUpload(pending.file, pending.hash);
        }}
      />
    </div>
  );
}
```

- [ ] **Step 9: Run tests to verify they pass**

Run: `npm test -- Documents DuplicateDialog`
Expected: PASS.

- [ ] **Step 10: Typecheck + commit**

```bash
npx tsc -p . --noEmit
git add src/features/documents/DuplicateDialog.tsx src/test/DuplicateDialog.test.tsx \
  src/features/documents/DocumentsList.tsx src/features/documents/DocumentCard.tsx src/test/Documents.test.tsx
git commit -m "feat(web): duplicate-document guard on the Documents page"
```

---

## Task 5: In-chat attach de-dup (reuse existing → pin)

**Files:**
- Modify: `src/features/chat/Chat.tsx`
- Test: `src/test/Chat.test.tsx`

**Interfaces:**
- Consumes: `hashFile` (Task 3), `DuplicateDialog` (Task 4), `contentHash`/`filename` on `documents.list` rows.
- Produces: when a chat attachment duplicates an existing document, "Use existing" pins the existing doc instead of uploading a second copy.

- [ ] **Step 1: Write the failing test** (append to `src/test/Chat.test.tsx`)

```tsx
test("attaching a duplicate opens the dialog; Use existing pins without re-uploading", async () => {
  mockedUseUIMessages.mockReturnValue(baseMessages as never);
  renderChat();

  const input = document.querySelector('input[type="file"]') as HTMLInputElement;
  const file = new File([new Uint8Array([1])], "report.pdf", { type: "application/pdf" });
  fireEvent.change(input, { target: { files: [file] } });

  await screen.findByText("You already have this file");
  fireEvent.click(screen.getByRole("button", { name: /use existing/i }));

  // The existing document is now attached as a chip (rendered by AttachmentCard).
  await waitFor(() =>
    expect(screen.getAllByText("report.pdf").length).toBeGreaterThan(0),
  );
});
```

Extend the file's top-level mocks so a matching document exists and hashing is deterministic. Add to the existing `convex/react` mock's `useQuery` the `documents.list` branch returning one ready doc, and mock content-hash:

```tsx
vi.mock("@/features/documents/content-hash", () => ({
  hashFile: vi.fn(async () => "hash-abc"),
  sha256Hex: vi.fn(async () => "hash-abc"),
}));
```

And change the existing `documents.list` mock branch (currently `return []`) to:

```tsx
    if (getFunctionName(q) === getFunctionName(api.documents.list))
      return [
        {
          _id: "d1",
          filename: "report.pdf",
          kind: "pdf",
          status: "ready",
          sizeBytes: 10,
          contentHash: "hash-abc",
          createdAt: 1,
        },
      ];
```

(The other Chat tests don't assert on `documents.list` contents, so returning this row is safe; verify they still pass in Step 4.)

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- Chat`
Expected: FAIL — no duplicate dialog on attach.

- [ ] **Step 3: Implement the chat attach de-dup** in `src/features/chat/Chat.tsx`

3a. Add imports (next to the other feature imports):

```tsx
import DuplicateDialog from "@/features/documents/DuplicateDialog";
import { hashFile } from "@/features/documents/content-hash";
```

3b. Widen the `documents` query typing so filename/contentHash are usable. Replace the `documents` declaration (lines 51-54):

```tsx
  const documents = (useQuery(api.documents.list) ?? []) as Array<{
    _id: string;
    filename: string;
    kind: string;
    sizeBytes: number;
    status: string;
    contentHash?: string;
  }>;
```

3c. Add duplicate state near the other attach state (after `pendingAttachments`, ~line 64):

```tsx
  // A chat attachment awaiting a duplicate decision (same name + same bytes).
  const [attachDup, setAttachDup] = useState<{ file: File; hash: string } | null>(null);
```

3d. Refactor `handleAttach` to do the pre-flight, and factor the upload into `doAttachUpload`. Replace the whole `handleAttach` function (lines 197-227) with:

```tsx
  async function doAttachUpload(file: File, contentHash: string) {
    setUploadBusy(true);
    try {
      const url = await generateUploadUrl();
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": file.type },
        body: file,
      });
      const { storageId } = await res.json();
      const documentId = await createDocument({
        storageId,
        filename: file.name,
        mimeType: file.type,
        sizeBytes: file.size,
        contentHash,
      });
      setPendingAttachments((prev) => [
        ...prev,
        {
          docId: documentId as unknown as string,
          filename: file.name,
          kind: kindFromFilename(file.name),
          sizeBytes: file.size,
        },
      ]);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Upload failed");
    } finally {
      setUploadBusy(false);
    }
  }

  // Attach the already-uploaded document (no new copy) — the "reference the
  // existing document" path when the user confirms a duplicate.
  function attachExisting(docId: string) {
    const doc = documents.find((d) => d._id === docId);
    if (!doc) return;
    setPendingAttachments((prev) =>
      prev.some((a) => a.docId === docId)
        ? prev
        : [
            ...prev,
            {
              docId: doc._id,
              filename: doc.filename,
              kind: doc.kind || kindFromFilename(doc.filename),
              sizeBytes: doc.sizeBytes,
            },
          ],
    );
  }

  async function handleAttach(file: File) {
    const hash = await hashFile(file);
    const existing = documents.find(
      (d) =>
        d.filename === file.name &&
        d.contentHash === hash &&
        (d.status === "ready" || d.status === "parsing"),
    );
    if (existing) {
      setAttachDup({ file, hash });
      return;
    }
    await doAttachUpload(file, hash);
  }
```

3e. Render the dialog. Just before the final closing `</div>` of the component's outer `return` (after the Composer block, before line 401's `</div>`... place it as a sibling of the `chat-canvas` div, right before the outermost closing tag):

```tsx
      <DuplicateDialog
        open={attachDup !== null}
        filename={attachDup?.file.name ?? ""}
        onOpenChange={(open) => {
          if (!open) setAttachDup(null);
        }}
        onUseExisting={() => {
          const pending = attachDup;
          setAttachDup(null);
          if (pending) {
            const existing = documents.find(
              (d) =>
                d.filename === pending.file.name && d.contentHash === pending.hash,
            );
            if (existing) attachExisting(existing._id);
          }
        }}
        onUploadAnyway={() => {
          const pending = attachDup;
          setAttachDup(null);
          if (pending) void doAttachUpload(pending.file, pending.hash);
        }}
      />
```

3f. Reset `attachDup` on thread switch — add `setAttachDup(null);` inside the `threadId` reset effect (the one edited in Task 2 step 3e).

- [ ] **Step 4: Run tests to verify they pass**

Run: `npm test -- Chat`
Expected: PASS (all Chat tests, including the new attach-dedup test and the Task 2 scroll test).

- [ ] **Step 5: Typecheck + commit**

```bash
npx tsc -p . --noEmit
git add src/features/chat/Chat.tsx src/test/Chat.test.tsx
git commit -m "feat(web): in-chat attach de-dup — reuse existing document via pin"
```

---

## Task 6: `listDocuments` tool — enumerate the full inventory in chat

**Files:**
- Modify: `convex/documents.ts`, `convex/tools.ts`, `convex/agent.ts`
- Test: `convex/documents.test.ts`, `convex/tools.test.ts`

**Interfaces:**
- Consumes: `requireCallerUserId(ctx)` (existing in `tools.ts`), the `documents` `by_user` index.
- Produces: `internal.documents.listForUser({ userId })` returning
  `Array<{ filename: string; kind: string; status: string; sizeBytes: number; createdAt: number }>`;
  and a `listDocuments` agent tool (no input) returning a formatted text block.

- [ ] **Step 1: Write the failing internalQuery test** (append to `convex/documents.test.ts`)

```ts
test("listForUser returns only the caller's documents", async () => {
  const t = convexTest(schema, modules);
  const { userId: aliceId } = await asNewUser(t, "alice-list@x.com");
  const { userId: bobId } = await asNewUser(t, "bob-list@x.com");
  await t.run(async (ctx) => {
    const storageId = await ctx.storage.store(new Blob([new Uint8Array([1])]));
    await ctx.db.insert("documents", {
      userId: aliceId, storageId, filename: "a.pdf", mimeType: "application/pdf",
      kind: "pdf", sizeBytes: 1, status: "ready", chunkCount: 1, createdAt: 1,
    });
    await ctx.db.insert("documents", {
      userId: bobId, storageId, filename: "b.pdf", mimeType: "application/pdf",
      kind: "pdf", sizeBytes: 1, status: "ready", chunkCount: 1, createdAt: 1,
    });
  });
  const rows = await t.run((ctx) =>
    (ctx as never as { runQuery: unknown }) // use the internal query directly:
      ? import("./_generated/api").then(async ({ internal }) =>
          ctx.runQuery(internal.documents.listForUser, { userId: aliceId }),
        )
      : [],
  );
  const list = (await rows) as Array<{ filename: string }>;
  expect(list).toHaveLength(1);
  expect(list[0].filename).toBe("a.pdf");
});
```

> If calling an `internalQuery` via `ctx.runQuery` inside `t.run` is awkward in this codebase's convex-test setup, use the simpler established pattern already used by other internal queries in this suite: `await t.query(internal.documents.listForUser, { userId: aliceId })` if the suite exposes internal calls that way, or replicate `knowledge.test.ts`'s approach for `internalQuery`. Keep the assertions (only Alice's one doc) identical.

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- documents`
Expected: FAIL — `internal.documents.listForUser` does not exist.

- [ ] **Step 3: Implement `listForUser`** in `convex/documents.ts`

Add the import at the top (alongside the existing `query, mutation` import):

```ts
import { query, mutation, internalQuery } from "./_generated/server";
```

Add the internal query (after `list`):

```ts
// Full document inventory for a user — the backing query for the
// `listDocuments` agent tool. internalQuery so it's only reachable server-side
// with a userId resolved from the authenticated caller (never from a client).
export const listForUser = internalQuery({
  args: { userId: v.id("users") },
  handler: async (ctx, { userId }) => {
    const docs = await ctx.db
      .query("documents")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .order("desc")
      .collect();
    return docs.map((d) => ({
      filename: d.filename,
      kind: d.kind,
      status: d.status,
      sizeBytes: d.sizeBytes,
      createdAt: d.createdAt,
    }));
  },
});
```

- [ ] **Step 4: Run the internalQuery test**

Run: `npm test -- documents`
Expected: PASS.

- [ ] **Step 5: Write the failing tool test** (append to `convex/tools.test.ts`)

```ts
test("listDocuments scopes to ctx.userId and formats the inventory", async () => {
  const runQuery = vi.fn(async (_ref: unknown, _args: { userId: string }) => [
    { filename: "a.pdf", kind: "pdf", status: "ready", sizeBytes: 2048, createdAt: 1 },
    { filename: "b.txt", kind: "txt", status: "parsing", sizeBytes: 10, createdAt: 2 },
  ]);
  const { listDocuments } = await import("./tools");
  const tool = withCtx(listDocuments, { userId: "alice_id", runQuery });
  const result = await tool.execute!({}, { toolCallId: "t1", messages: [] } as any);

  const [, args] = runQuery.mock.calls[0];
  expect(args).toEqual({ userId: "alice_id" });
  expect(result).toContain("a.pdf");
  expect(result).toContain("b.txt");
  expect(result).toContain("parsing");
});

test("listDocuments fails closed without a caller in scope", async () => {
  const { listDocuments } = await import("./tools");
  const tool = withCtx(listDocuments, {});
  await expect(
    tool.execute!({}, { toolCallId: "t1", messages: [] } as any),
  ).rejects.toThrow(/authenticated user/i);
});
```

- [ ] **Step 6: Run test to verify it fails**

Run: `npm test -- tools`
Expected: FAIL — `listDocuments` not exported from `./tools`.

- [ ] **Step 7: Implement the `listDocuments` tool** in `convex/tools.ts`

Add to the imports at the top:

```ts
import { createTool, type ToolCtx } from "@convex-dev/agent";
```
(already present — no change) — and ensure `internal` and `Id` are imported (they are).

Append the tool:

```ts
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
```

- [ ] **Step 8: Run the tool test**

Run: `npm test -- tools`
Expected: PASS.

- [ ] **Step 9: Register the tool + instruction** in `convex/agent.ts`

Update the import:

```ts
import { searchKnowledge, pinpoint, listDocuments } from "./tools";
```

Add a sentence to `instructions` (append to the existing second string):

```ts
    "Use searchKnowledge for questions about the user's documents or meetings; use pinpoint to find exact values (dates, amounts, clause numbers) within a known source. When the user asks to list, count, or enumerate their documents (rather than asking a content question), use listDocuments and present the full list. Ground every claim in the returned context and cite sources with [n] matching the numbered sources provided. Never cite a source that wasn't provided; if the context is insufficient, say so.",
```

Register the tool:

```ts
  tools: { searchKnowledge, pinpoint, listDocuments },
```

- [ ] **Step 10: Codegen + full gate + commit**

```bash
npx convex codegen
npx tsc -p . --noEmit
npm test
npm run build
git add convex/documents.ts convex/tools.ts convex/agent.ts convex/_generated \
  convex/documents.test.ts convex/tools.test.ts
git commit -m "feat(web): listDocuments tool — enumerate full document inventory in chat"
```

---

## Task 7: STATUS.md + gate + browser smoke

**Files:**
- Modify: `STATUS.md`

- [ ] **Step 1: Run the full gate**

Run (from `apps/web`): `npx convex codegen && npx tsc -p . --noEmit && npm test && npm run build`
Expected: all clean/green.

- [ ] **Step 2: Update STATUS.md**

Add a **C5** row to the web slices table and to the "Now (web)" line summarizing: chat stick-to-bottom + jump-to-latest, exact-duplicate document guard (name+SHA-256 → confirm/reuse), and the `listDocuments` tool. Update "Last updated" to 2026-07-13. Move the relevant "Todo ⬜" chat/doc items to "Working ✅" as appropriate. Keep it honest — mark ✅ only what the gate verified; note browser smoke as pending until run.

- [ ] **Step 3: Browser smoke (manual, after gate green)**

With `npx convex dev` running and signed in:
1. Send a few messages; confirm the view snaps to the newest and follows the streamed reply; scroll up mid-stream and confirm the "Jump to latest" pill appears and stops the auto-yank.
2. Upload a file on the Documents page, then upload the exact same file again → confirm the duplicate dialog; "Use existing" adds no second copy; edit the file's bytes and re-upload same name → uploads normally.
3. In chat, attach the same file twice → dialog; "Use existing" pins the existing doc (chip appears) with no new upload.
4. Ask the assistant "list my documents" → confirm it enumerates every document, including ones that aren't content-matched.

- [ ] **Step 4: Commit STATUS.md**

```bash
git add STATUS.md
git commit -m "docs(status): C5 — chat auto-scroll, doc de-dup, listDocuments"
```

---

## Self-Review

**Spec coverage:**
- §1 Auto-scroll → Tasks 1 (hook) + 2 (wiring, pill, send-force, thread-switch). ✅
- §2 Duplicate guard → Tasks 3 (hash + `contentHash` + `create`) + 4 (dialog + Documents page) + 5 (chat attach reuse-via-pin). ✅
- §3 List documents → Task 6 (`listForUser` + `listDocuments` tool + agent wiring). ✅
- Security/privacy (client-side hash, userId-scoped internalQuery, fail-closed tool) → Task 3/6 + Global Constraints. ✅
- Gate + STATUS → Task 7. ✅

**Placeholder scan:** every code step includes full code; no TBD/TODO. The two "if the existing test differs, adapt" notes are guidance for matching established mocks, not placeholders — the concrete assertions and behavior are fully specified.

**Type consistency:** `hashFile`/`sha256Hex` (Task 3) used identically in Tasks 4/5; `DuplicateDialog` prop shape identical in Tasks 4/5; `contentHash` optional across schema/create/rows; `listForUser` return shape (filename/kind/status/sizeBytes/createdAt) matches the `listDocuments` consumer and its test; `documents.create` arg list consistent across `DocumentsList.doUpload` and `Chat.doAttachUpload`.
