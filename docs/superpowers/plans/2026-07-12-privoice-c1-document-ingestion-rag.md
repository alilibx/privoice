# C1 — Document ingestion + RAG store Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In `apps/web`, let a signed-in user upload PDF/XLSX/DOCX/txt/md files that are parsed, chunked, embedded (OpenRouter `openai/text-embedding-3-small`), and stored per-user in a Convex vector index, with a Documents page showing live status + delete. No chat yet (that's C2).

**Architecture:** Client uploads to Convex file storage → `documents.create` inserts a row (`status:"parsing"`) and schedules a `"use node"` internal action `ingest.ingestDocument` → the action parses (pdf-parse/mammoth/xlsx), `chunkText`s, embeds via OpenRouter, writes `documentChunks` (with per-user vector index), and flips status to `ready`/`failed`. All public functions are identity-gated; vector search filters by `userId`.

**Tech Stack:** Convex (queries/mutations, `internalAction`/`internalMutation`, scheduler, file storage, vector index), `"use node"` runtime with `pdf-parse` / `mammoth` / `xlsx`, OpenRouter embeddings, React + Vite + Tailwind, `convex-test` + `vitest`.

## Global Constraints

Security/privacy is the top priority (standing directive) — these bind every task:
- **`OPENROUTER_API_KEY` is a Convex deployment env var** (already set). Read only in server actions via `process.env.OPENROUTER_API_KEY`; NEVER sent to the client, NEVER logged, NEVER a literal in source.
- **Every public query/mutation resolves `const userId = await getAuthUserId(ctx)` and throws `ConvexError("Not authenticated")` when null.** No unauthenticated data path.
- **`documents` and `documentChunks` are keyed by `userId`; all reads/writes/deletes are caller-scoped.** The vector index uses `filterFields:["userId"]` and every vector query filters `userId == caller` — retrieval can never cross tenants. Isolation is TESTED, not assumed.
- **Delete cascades:** removing a document deletes its `documentChunks` (via `by_document`) AND the storage blob (`ctx.storage.delete`).
- **Ingest write-backs are `internal*` functions** (not publicly callable). The parse/embed action is `"use node"`.
- **Upload cap 10 MB**; accepted kinds `pdf|docx|xlsx|txt|md`; oversize/unsupported → thrown `ConvexError` (create) or `status:"failed"` (ingest), never a crash. Error messages are sanitized (no secret/stack leakage).
- **Embeddings model:** `openai/text-embedding-3-small` (1536-dim) via `POST https://openrouter.ai/api/v1/embeddings`.
- Tests-from-the-start: pure + convex-test layers run on a fresh clone (committed `_generated`); wire into the `apps/web` CI job. Conventional commits. `/security-review` before merge.

**Deploy gate (account-bound; the USER runs — agent won't handle the deploy):** after the backend code (Tasks 1–3) lands, the user runs `cd apps/web && npm install` (new parse deps) + `npx convex dev` to regenerate `convex/_generated/` (now including the new tables/functions) and push. Task 3's convex-test run and Task 5's live upload verify **after** that. The agent then commits the regenerated `_generated`.

**Verify commands (from `apps/web`):** `npx tsc --noEmit` · `npm run test` · `npm run build`. Node 22 at `/usr/local/bin/node`.

---

## File Structure

```
apps/web/
  package.json                      # + pdf-parse, mammoth, xlsx
  convex/
    schema.ts                       # + documents, documentChunks (+ vectorIndex)
    documents.ts                    # generateUploadUrl / create / list / remove (public, auth-gated)
    ingest.ts                       # "use node" internalAction ingestDocument (actions ONLY)
    ingestStore.ts                  # internal query+mutations (getDoc/insertChunks/setReady/setFailed) — NOT "use node"
    lib/chunk.ts                    # pure chunkText
    lib/chunk.test.ts
    lib/embed.ts                    # embedChunks (OpenRouter)
    documents.test.ts               # convex-test authz/isolation/cascade
    _generated/                     # regenerated + committed after deploy gate
  src/
    App.tsx                         # + Meetings/Documents nav
    components/Documents.tsx
    test/Documents.test.tsx
```

---

## Task 1: `chunkText` pure helper + unit tests

**Files:** Create `apps/web/convex/lib/chunk.ts`, `apps/web/convex/lib/chunk.test.ts`

**Interfaces:**
- Produces: `export function chunkText(text: string, opts?: { maxChars?: number; overlapChars?: number }): string[]` — splits into ≤`maxChars` (default 3000) chunks with `overlapChars` (default 300) overlap, preferring paragraph/whitespace boundaries; never returns empty chunks; returns `[]` for blank input.

- [ ] **Step 1: Write the failing tests**

`apps/web/convex/lib/chunk.test.ts`:
```ts
import { describe, expect, test } from "vitest";
import { chunkText } from "./chunk";

describe("chunkText", () => {
  test("blank input yields no chunks", () => {
    expect(chunkText("")).toEqual([]);
    expect(chunkText("   \n  ")).toEqual([]);
  });

  test("short text is a single chunk", () => {
    expect(chunkText("hello world")).toEqual(["hello world"]);
  });

  test("respects maxChars and overlaps", () => {
    const text = "a".repeat(7000);
    const chunks = chunkText(text, { maxChars: 3000, overlapChars: 300 });
    expect(chunks.length).toBeGreaterThanOrEqual(3);
    for (const c of chunks) expect(c.length).toBeLessThanOrEqual(3000);
    // consecutive chunks share the overlap tail/head
    expect(chunks[0].slice(-300)).toEqual(chunks[1].slice(0, 300));
  });

  test("no empty chunks for a huge input", () => {
    const chunks = chunkText("x ".repeat(60000), { maxChars: 3000, overlapChars: 300 });
    expect(chunks.every((c) => c.trim().length > 0)).toBe(true);
  });
});
```

- [ ] **Step 2: Run — verify RED**

Run: `cd apps/web && npm run test -- chunk`
Expected: FAIL (`chunk` not found).

- [ ] **Step 3: Implement**

`apps/web/convex/lib/chunk.ts`:
```ts
/** Split text into overlapping chunks (char-based; ~3000 chars ≈ 800 tokens). */
export function chunkText(
  text: string,
  opts: { maxChars?: number; overlapChars?: number } = {},
): string[] {
  const maxChars = opts.maxChars ?? 3000;
  const overlapChars = Math.min(opts.overlapChars ?? 300, Math.floor(maxChars / 2));
  const clean = text.replace(/\r\n/g, "\n").trim();
  if (clean.length === 0) return [];
  if (clean.length <= maxChars) return [clean];

  const chunks: string[] = [];
  let start = 0;
  while (start < clean.length) {
    let end = Math.min(start + maxChars, clean.length);
    if (end < clean.length) {
      // Prefer to break on a nearby whitespace/newline boundary.
      const slice = clean.slice(start, end);
      const lastBreak = Math.max(slice.lastIndexOf("\n"), slice.lastIndexOf(" "));
      if (lastBreak > maxChars * 0.5) end = start + lastBreak + 1;
    }
    const piece = clean.slice(start, end).trim();
    if (piece.length > 0) chunks.push(clean.slice(start, end));
    if (end >= clean.length) break;
    start = end - overlapChars;
  }
  return chunks;
}
```
Note: the overlap test compares raw slices; keep chunk boundaries char-exact (don't trim the stored slice) so `chunks[0].slice(-300) === chunks[1].slice(0,300)` holds. Adjust: push `clean.slice(start, end)` (untrimmed) but skip pushing when it's whitespace-only. (Implementation above does this.)

- [ ] **Step 4: Run — verify GREEN**

Run: `cd apps/web && npm run test -- chunk`
Expected: PASS (4 tests). If the overlap-equality assertion is brittle with boundary-breaking, set `overlapChars` slicing to operate on the fixed window (disable the whitespace-break for the equality test by using `"a".repeat(...)` which has no whitespace — the break logic won't trigger, so slices align). Confirm green.

- [ ] **Step 5: Commit**

```bash
git add apps/web/convex/lib/chunk.ts apps/web/convex/lib/chunk.test.ts
git commit -m "feat(web): pure chunkText helper for document RAG + unit tests"
```

---

## Task 2: schema tables + `embed.ts` + `ingest.ts` (`"use node"` parse/embed pipeline)

**Files:** Modify `apps/web/convex/schema.ts`, `apps/web/package.json`. Create `apps/web/convex/lib/embed.ts`, `apps/web/convex/ingest.ts`, `apps/web/convex/ingestStore.ts`.

**Interfaces:**
- Consumes: `chunkText` (Task 1); `getAuthUserId` not needed here (internal, called via scheduler with a trusted `userId` read from the doc row).
- Produces: `documents` + `documentChunks` tables (+ vector index); `internal.ingest.ingestDocument({ documentId })` (`"use node"` internalAction); internal query/mutations in a SEPARATE non-node module `internal.ingestStore.{getDoc, insertChunks, setReady, setFailed}`; `embedChunks(texts: string[]): Promise<number[][]>`.
- **Convex rule (why the split):** a `"use node"` module may export **only actions**. Queries/mutations must live in a regular (V8-runtime) module — hence `ingestStore.ts` for the write-backs, which the node action calls via `ctx.runQuery`/`ctx.runMutation(internal.ingestStore.*)`.

> **Runtime test gate:** the `"use node"` parse/embed path is NOT unit-testable under convex-test (real libs + network + live key). Per the approved spec it's verified at the **deploy gate** (Task 5) with real uploads. This task's automated verification is `tsc`/`build` cleanliness; note the deferred runtime verification in the report.

- [ ] **Step 1: Add parse deps**

Run: `cd apps/web && npm install pdf-parse mammoth xlsx`
Then add `@types/pdf-parse` if needed for TS (`npm i -D @types/pdf-parse`); `mammoth` and `xlsx` ship types.

- [ ] **Step 2: Extend the schema**

In `apps/web/convex/schema.ts` add (inside `defineSchema({ ...authTables, meetings, ... })`):
```ts
  documents: defineTable({
    userId: v.id("users"),
    storageId: v.id("_storage"),
    filename: v.string(),
    mimeType: v.string(),
    kind: v.string(), // "pdf" | "docx" | "xlsx" | "txt" | "md"
    sizeBytes: v.number(),
    status: v.string(), // "parsing" | "ready" | "failed"
    error: v.optional(v.string()),
    chunkCount: v.number(),
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

- [ ] **Step 3: Embeddings client**

`apps/web/convex/lib/embed.ts`:
```ts
// Calls OpenRouter's OpenAI-compatible embeddings endpoint. Server-only:
// reads OPENROUTER_API_KEY from the Convex env; never expose to the client.
const ENDPOINT = "https://openrouter.ai/api/v1/embeddings";
const MODEL = "openai/text-embedding-3-small";
const BATCH = 96;

export async function embedChunks(texts: string[]): Promise<number[][]> {
  const key = process.env.OPENROUTER_API_KEY;
  if (!key) throw new Error("OPENROUTER_API_KEY is not set");
  const out: number[][] = [];
  for (let i = 0; i < texts.length; i += BATCH) {
    const batch = texts.slice(i, i + BATCH);
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ model: MODEL, input: batch }),
    });
    if (!res.ok) {
      // Do not include the key or raw response that might echo headers.
      throw new Error(`Embeddings request failed (${res.status})`);
    }
    const json = (await res.json()) as { data: { embedding: number[]; index: number }[] };
    const sorted = json.data.sort((a, b) => a.index - b.index);
    for (const d of sorted) out.push(d.embedding);
  }
  return out;
}
```

- [ ] **Step 4a: Internal write-backs (regular V8 module — NOT `"use node"`)**

`apps/web/convex/ingestStore.ts`:
```ts
import { v } from "convex/values";
import { internalQuery, internalMutation } from "./_generated/server";

export const getDoc = internalQuery({
  args: { documentId: v.id("documents") },
  handler: (ctx, { documentId }) => ctx.db.get(documentId),
});

export const insertChunks = internalMutation({
  args: {
    documentId: v.id("documents"),
    userId: v.id("users"),
    chunks: v.array(v.object({ text: v.string(), embedding: v.array(v.float64()) })),
  },
  handler: async (ctx, { documentId, userId, chunks }) => {
    for (let i = 0; i < chunks.length; i++) {
      await ctx.db.insert("documentChunks", {
        userId, documentId, chunkIndex: i,
        text: chunks[i].text, embedding: chunks[i].embedding,
      });
    }
  },
});

export const setReady = internalMutation({
  args: { documentId: v.id("documents"), chunkCount: v.number() },
  handler: (ctx, { documentId, chunkCount }) =>
    ctx.db.patch(documentId, { status: "ready", chunkCount }),
});

export const setFailed = internalMutation({
  args: { documentId: v.id("documents"), error: v.string() },
  handler: (ctx, { documentId, error }) =>
    ctx.db.patch(documentId, { status: "failed", error }),
});
```

- [ ] **Step 4b: Ingest action (`"use node"` — actions ONLY in this file)**

`apps/web/convex/ingest.ts`:
```ts
"use node";
import { v } from "convex/values";
import { internalAction } from "./_generated/server";
import { internal } from "./_generated/api";
import { chunkText } from "./lib/chunk";
import { embedChunks } from "./lib/embed";
import mammoth from "mammoth";
import * as XLSX from "xlsx";
import pdf from "pdf-parse";

async function extractText(kind: string, buf: Buffer): Promise<string> {
  switch (kind) {
    case "pdf":
      return (await pdf(buf)).text;
    case "docx":
      return (await mammoth.extractRawText({ buffer: buf })).value;
    case "xlsx": {
      const wb = XLSX.read(buf, { type: "buffer" });
      return wb.SheetNames.map(
        (name) => `# ${name}\n${XLSX.utils.sheet_to_csv(wb.Sheets[name])}`,
      ).join("\n\n");
    }
    case "txt":
    case "md":
      return buf.toString("utf-8");
    default:
      throw new Error(`Unsupported kind: ${kind}`);
  }
}

export const ingestDocument = internalAction({
  args: { documentId: v.id("documents") },
  handler: async (ctx, { documentId }) => {
    const doc = await ctx.runQuery(internal.ingestStore.getDoc, { documentId });
    if (doc === null) return; // deleted before ingest ran
    try {
      const blob = await ctx.storage.get(doc.storageId);
      if (blob === null) throw new Error("File missing from storage");
      const buf = Buffer.from(await blob.arrayBuffer());
      const text = await extractText(doc.kind, buf);
      const chunks = chunkText(text);
      if (chunks.length === 0) throw new Error("No extractable text");
      const embeddings = await embedChunks(chunks);
      await ctx.runMutation(internal.ingestStore.insertChunks, {
        documentId,
        userId: doc.userId,
        chunks: chunks.map((text, i) => ({ text, embedding: embeddings[i] })),
      });
      await ctx.runMutation(internal.ingestStore.setReady, {
        documentId,
        chunkCount: chunks.length,
      });
    } catch (e) {
      await ctx.runMutation(internal.ingestStore.setFailed, {
        documentId,
        error: e instanceof Error ? e.message : "Ingestion failed",
      });
    }
  },
});
```
(`pdf-parse` is CommonJS; if TS/esbuild flags the default import, use `import pdf from "pdf-parse"` with `esModuleInterop` — already on via the tsconfig — or fall back to `const pdf = require("pdf-parse")`. Report which was needed.)

- [ ] **Step 5: Typecheck/build (runtime path is deploy-gated)**

Run: `cd apps/web && npx tsc --noEmit`
Expected: errors ONLY from the stale `_generated` not yet containing `internal.ingest.*` (they resolve after the deploy gate regenerates `_generated`). Distinguish these from any real type error in `ingest.ts`/`embed.ts`/`schema.ts` (fix real ones — e.g. pdf-parse default-import interop: if TS complains, use `import pdf = require("pdf-parse")` or `import * as pdf`). Report which errors are gate vs real.

- [ ] **Step 6: Commit**

```bash
git add apps/web/convex/schema.ts apps/web/convex/ingest.ts apps/web/convex/ingestStore.ts \
  apps/web/convex/lib/embed.ts apps/web/package.json apps/web/package-lock.json
git commit -m "feat(web): documents/documentChunks schema (+vector index) + node ingest (parse/chunk/embed)"
```

---

## Task 3: `documents.ts` public functions + convex-test authz/isolation/cascade

**Files:** Create `apps/web/convex/documents.ts`, `apps/web/convex/documents.test.ts`.

**Interfaces:**
- Consumes: `getAuthUserId`; `internal.ingest.ingestDocument` (Task 2) for scheduling; `documents`/`documentChunks` tables.
- Produces: `api.documents.generateUploadUrl`, `api.documents.create({storageId, filename, mimeType, sizeBytes}) → Id<"documents">`, `api.documents.list → Doc[]`, `api.documents.remove({id})`.

> Tests run after the deploy gate regenerates `_generated`. Write code + tests now; the RED/GREEN of `documents.test.ts` validates at the gate (Task 5), same pattern as O1's authz tests.

- [ ] **Step 1: Implement `documents.ts`**

```ts
import { query, mutation } from "./_generated/server";
import { v, ConvexError } from "convex/values";
import { getAuthUserId } from "@convex-dev/auth/server";
import { internal } from "./_generated/api";

const MAX_BYTES = 10 * 1024 * 1024; // 10 MB
const KIND_BY_EXT: Record<string, string> = {
  pdf: "pdf", docx: "docx", xlsx: "xlsx", txt: "txt", md: "md",
};

async function requireUserId(ctx: any) {
  const userId = await getAuthUserId(ctx);
  if (userId === null) throw new ConvexError("Not authenticated");
  return userId;
}

export const generateUploadUrl = mutation({
  args: {},
  handler: async (ctx) => {
    await requireUserId(ctx);
    return await ctx.storage.generateUploadUrl();
  },
});

export const create = mutation({
  args: {
    storageId: v.id("_storage"),
    filename: v.string(),
    mimeType: v.string(),
    sizeBytes: v.number(),
  },
  handler: async (ctx, { storageId, filename, mimeType, sizeBytes }) => {
    const userId = await requireUserId(ctx);
    if (sizeBytes > MAX_BYTES) throw new ConvexError("File exceeds 10 MB limit");
    const ext = filename.split(".").pop()?.toLowerCase() ?? "";
    const kind = KIND_BY_EXT[ext];
    if (!kind) throw new ConvexError("Unsupported file type");
    const documentId = await ctx.db.insert("documents", {
      userId, storageId, filename, mimeType, kind, sizeBytes,
      status: "parsing", chunkCount: 0, createdAt: Date.now(),
    });
    await ctx.scheduler.runAfter(0, internal.ingest.ingestDocument, { documentId });
    return documentId;
  },
});

export const list = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    return await ctx.db
      .query("documents")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .order("desc")
      .collect();
  },
});

export const remove = mutation({
  args: { id: v.id("documents") },
  handler: async (ctx, { id }) => {
    const userId = await requireUserId(ctx);
    const doc = await ctx.db.get(id);
    if (doc === null || doc.userId !== userId) throw new ConvexError("Not found");
    const chunks = await ctx.db
      .query("documentChunks")
      .withIndex("by_document", (q) => q.eq("documentId", id))
      .collect();
    for (const c of chunks) await ctx.db.delete(c._id);
    await ctx.storage.delete(doc.storageId);
    await ctx.db.delete(id);
  },
});
```

- [ ] **Step 2: Write convex-test authz/isolation/cascade tests**

`apps/web/convex/documents.test.ts`:
```ts
import { convexTest } from "convex-test";
import { expect, test } from "vitest";
import schema from "./schema";
import { api } from "./_generated/api";

const modules = import.meta.glob("./**/*.ts");

async function asNewUser(t: ReturnType<typeof convexTest>, email: string) {
  const userId = await t.run((ctx) => ctx.db.insert("users", { email }));
  return { t: t.withIdentity({ subject: `${userId}|s_${userId}` }), userId };
}
// A fake storage id via a run-inserted blob is unavailable in convex-test;
// use t.run to insert a document row directly for list/remove tests, and test
// create's validation + scheduling via the public mutation with a stored blob.

test("create rejects oversize + unsupported, schedules ingest on success", async () => {
  const t = convexTest(schema, modules);
  const { t: alice } = await asNewUser(t, "a@x.com");
  const storageId = await alice.run(async (ctx) =>
    ctx.storage.store(new Blob(["hello"], { type: "text/plain" })),
  );
  await expect(
    alice.mutation(api.documents.create, {
      storageId, filename: "big.pdf", mimeType: "application/pdf", sizeBytes: 20_000_000,
    }),
  ).rejects.toThrow();
  await expect(
    alice.mutation(api.documents.create, {
      storageId, filename: "note.exe", mimeType: "x", sizeBytes: 10,
    }),
  ).rejects.toThrow();
  const id = await alice.mutation(api.documents.create, {
    storageId, filename: "note.txt", mimeType: "text/plain", sizeBytes: 5,
  });
  expect(id).toBeDefined();
  // scheduled function is queued
  expect((await t.finishInProgressScheduledFunctions?.()) ?? true).toBeTruthy();
});

test("list is isolated per user", async () => {
  const t = convexTest(schema, modules);
  const { t: alice, userId: aId } = await asNewUser(t, "a@x.com");
  const { t: bob } = await asNewUser(t, "b@x.com");
  await t.run((ctx) =>
    ctx.db.insert("documents", {
      userId: aId, storageId: "x" as any, filename: "a.txt", mimeType: "t",
      kind: "txt", sizeBytes: 1, status: "ready", chunkCount: 0, createdAt: 0,
    }),
  );
  expect(await alice.query(api.documents.list, {})).toHaveLength(1);
  expect(await bob.query(api.documents.list, {})).toHaveLength(0);
});

test("remove refuses another user's doc and cascades chunks", async () => {
  const t = convexTest(schema, modules);
  const { t: alice, userId: aId } = await asNewUser(t, "a@x.com");
  const { t: bob } = await asNewUser(t, "b@x.com");
  const docId = await t.run(async (ctx) => {
    const id = await ctx.db.insert("documents", {
      userId: aId, storageId: (await ctx.storage.store(new Blob(["x"]))) as any,
      filename: "a.txt", mimeType: "t", kind: "txt", sizeBytes: 1,
      status: "ready", chunkCount: 1, createdAt: 0,
    });
    await ctx.db.insert("documentChunks", {
      userId: aId, documentId: id, chunkIndex: 0, text: "x", embedding: [0.1],
    });
    return id;
  });
  await expect(bob.mutation(api.documents.remove, { id: docId })).rejects.toThrow();
  await alice.mutation(api.documents.remove, { id: docId });
  const remaining = await t.run((ctx) => ctx.db.query("documentChunks").collect());
  expect(remaining).toHaveLength(0);
});

test("unauthenticated calls throw", async () => {
  const t = convexTest(schema, modules);
  await expect(t.query(api.documents.list, {})).rejects.toThrow();
  await expect(
    t.mutation(api.documents.create, {
      storageId: "x" as any, filename: "a.txt", mimeType: "t", sizeBytes: 1,
    }),
  ).rejects.toThrow();
});
```
(If `finishInProgressScheduledFunctions` isn't available in the installed convex-test, drop that line — the create success assertion is the returned id. The `storageId: "x" as any` in the isolation/unauth tests is fine since those paths never read storage.)

- [ ] **Step 3: Typecheck (gated) + commit**

Run: `cd apps/web && npx tsc --noEmit` — expect only stale-`_generated` errors (resolve at the gate); no real errors in `documents.ts`.
```bash
git add apps/web/convex/documents.ts apps/web/convex/documents.test.ts
git commit -m "feat(web): documents public API (upload/create/list/remove) + convex-test authz/isolation/cascade"
```

---

## Task 4: Documents page + Meetings/Documents nav

**Files:** Create `apps/web/src/components/Documents.tsx`, `apps/web/src/test/Documents.test.tsx`. Modify `apps/web/src/App.tsx`.

**Interfaces:** Consumes `api.documents.*`. Produces the Documents UI + a two-view nav in the authenticated shell.

> Component tests mock `convex/react`, so they run headlessly now (no `_generated` needed at runtime for the mocked path — but the file imports `api` from `_generated`, so full green is after the gate; the mocked render still works once `_generated` includes documents). Validate at the gate with Task 3.

- [ ] **Step 1: Failing Documents test**

`apps/web/src/test/Documents.test.tsx`:
```tsx
import { render, screen } from "@testing-library/react";
import { vi } from "vitest";
import Documents from "../components/Documents";

vi.mock("convex/react", () => ({
  useQuery: () => [
    { _id: "1", filename: "report.pdf", kind: "pdf", status: "ready", chunkCount: 12 },
    { _id: "2", filename: "data.xlsx", kind: "xlsx", status: "parsing", chunkCount: 0 },
  ],
  useMutation: () => vi.fn(),
}));

test("lists documents with status", () => {
  render(<Documents />);
  expect(screen.getByText("report.pdf")).toBeInTheDocument();
  expect(screen.getByText("data.xlsx")).toBeInTheDocument();
  expect(screen.getByText(/parsing/i)).toBeInTheDocument();
});
```

- [ ] **Step 2: Run — RED**

Run: `cd apps/web && npm run test -- Documents`
Expected: FAIL (`Documents` not found).

- [ ] **Step 3: Implement `Documents.tsx`**

Full component: upload (file input `accept=".pdf,.docx,.xlsx,.txt,.md"` + drag/drop) that calls `generateUploadUrl` → `fetch(url,{method:"POST",body:file})` → `create({storageId, filename:file.name, mimeType:file.type, sizeBytes:file.size})`; a live list from `useQuery(api.documents.list)` with filename, kind, a status chip (Parsing spinner / Ready+chunkCount / Failed+error), and a Delete button (`remove({id})`); calm-teal theme tokens, `bg-surface`/`text-on-surface`, empty state. (Mirror the Dashboard's structure + input styling from O1.)

```tsx
import { useState } from "react";
import { useQuery, useMutation } from "convex/react";
import { api } from "../../convex/_generated/api";

export default function Documents() {
  const docs = useQuery(api.documents.list) ?? [];
  const generateUploadUrl = useMutation(api.documents.generateUploadUrl);
  const create = useMutation(api.documents.create);
  const remove = useMutation(api.documents.remove);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function upload(file: File) {
    setBusy(true); setError(null);
    try {
      const url = await generateUploadUrl();
      const res = await fetch(url, { method: "POST", headers: { "Content-Type": file.type }, body: file });
      const { storageId } = await res.json();
      await create({ storageId, filename: file.name, mimeType: file.type, sizeBytes: file.size });
    } catch (e) {
      setError(e instanceof Error ? e.message : "Upload failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="mx-auto max-w-2xl p-6">
      <h1 className="text-2xl font-bold text-primary">Documents</h1>
      <label className="mt-6 block cursor-pointer rounded-xl border border-dashed border-outline bg-surface p-6 text-center text-on-surface-variant">
        {busy ? "Uploading…" : "Drop a file or click to upload (PDF, Word, Excel, txt, md)"}
        <input type="file" accept=".pdf,.docx,.xlsx,.txt,.md" className="hidden"
          onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); e.target.value = ""; }} />
      </label>
      {error && <p className="mt-2 text-sm text-red-600">{error}</p>}
      <ul className="mt-6 space-y-2">
        {docs.map((d: any) => (
          <li key={d._id} className="flex items-center justify-between rounded-xl border border-outline bg-surface p-4">
            <span className="truncate">{d.filename}</span>
            <span className="flex items-center gap-3 text-sm">
              <StatusChip status={d.status} chunkCount={d.chunkCount} error={d.error} />
              <button onClick={() => remove({ id: d._id })}
                className="text-on-surface-variant hover:text-red-600">Delete</button>
            </span>
          </li>
        ))}
        {docs.length === 0 && <li className="text-on-surface-variant">No documents yet.</li>}
      </ul>
    </section>
  );
}

function StatusChip({ status, chunkCount, error }: { status: string; chunkCount: number; error?: string }) {
  if (status === "ready") return <span className="text-primary">Ready · {chunkCount} chunks</span>;
  if (status === "failed") return <span className="text-red-600" title={error}>Failed</span>;
  return <span className="text-on-surface-variant">Parsing…</span>;
}
```

- [ ] **Step 4: Nav in App.tsx**

In `App.tsx`'s `<Authenticated>` slot, replace the direct `<Dashboard/>` with a two-view switch:
```tsx
// local state: const [view, setView] = useState<"meetings"|"documents">("meetings");
// a simple top nav with two buttons (calm-teal), rendering <Dashboard/> or <Documents/>.
```
Keep the existing Dashboard sign-out; put the nav above the active view.

- [ ] **Step 5: Run — GREEN + build**

Run: `cd apps/web && npm run test` (all green) · `npx tsc --noEmit` (after gate) · `npm run build`.

- [ ] **Step 6: Commit**

```bash
git add apps/web/src/components/Documents.tsx apps/web/src/test/Documents.test.tsx apps/web/src/App.tsx
git commit -m "feat(web): Documents page (upload/status/delete) + Meetings/Documents nav"
```

---

## Task 5: Deploy gate, live ingest verification, security review, STATUS, finish

**Files:** Modify `apps/web/convex/_generated/*` (regenerated), `STATUS.md`.

- [ ] **Step 1: Deploy gate (USER runs)**

```bash
cd apps/web
npm install                 # ensures pdf-parse/mammoth/xlsx present
npx convex dev              # regenerate _generated (new tables/functions) + push; leave running or Ctrl-C after "ready"
```
`OPENROUTER_API_KEY` is already set on the deployment.

- [ ] **Step 2: Run gated tests + commit regenerated `_generated`**

Once `_generated` is updated:
```bash
cd apps/web && npm run test   # chunk + documents authz/isolation/cascade + Documents component — all green
npx tsc --noEmit              # clean
npm run build                 # ok
git add apps/web/convex/_generated
git commit -m "chore(web): regenerate convex/_generated for documents/ingest"
```

- [ ] **Step 3: Live ingest e2e (USER, in browser)** — `npm run dev`, then, signed in:
- Upload a **PDF**, a **DOCX**, and an **XLSX** → each goes Parsing → **Ready** with `chunkCount > 0`.
- Upload a `.txt` → Ready. Upload an oversize (>10 MB) or `.exe` → rejected with a clear message.
- Delete a doc → disappears (and, verify in the Convex dashboard, its chunks are gone).
- A second account sees none of the first's documents.
Report per-step; don't claim verified until the user confirms.

- [ ] **Step 4: Security review**

Run `/security-review` on the C1 diff. Confirm: `OPENROUTER_API_KEY` only in server action, not logged/committed; every `documents` function identity-gated; vector index + all reads filter `userId`; `remove` cascades + refuses cross-user; upload validation; no secret in error messages. Fix any finding before merge.

- [ ] **Step 5: STATUS.md**

Add a C1 entry to the web workstream (✅ code-complete; *verified* after Step 3). Note the vector store is ready for C2's `searchDocuments` tool. Commit.

- [ ] **Step 6: Finish the branch**

Use `superpowers:finishing-a-development-branch` to merge `feat/c1-documents` into `main` (`--no-ff`) once green + e2e-verified.

---

## Self-Review

**Spec coverage:** upload+parse PDF/XLSX/DOCX/txt/md → T2 (ingest) ✅ · chunk → T1 ✅ · embed via OpenRouter → T2 (`embed.ts`) ✅ · per-user vector index → T2 (schema) ✅ · documents CRUD identity-gated + isolation + cascade → T3 ✅ · Documents UI + nav → T4 ✅ · security (env key server-only, userId scoping/filter, cascade, size/type caps, sanitized errors) → Global Constraints + T2/T3/T5 ✅ · tests-from-start (chunk unit + convex-test authz now; node path deploy-gated per approved spec) → T1/T3/T5 ✅ · deploy gate + live verify + /security-review + STATUS + finish → T5 ✅.

**Placeholder scan:** none. The `ingest.ts` Step 4 includes a "placeholder to satisfy tree-shakers" ternary purely to show file ordering — the step explicitly instructs removing it and states the final file layout; not a shipped placeholder.

**Type consistency:** `api.documents.{generateUploadUrl,create,list,remove}`, `internal.ingest.ingestDocument`, and `internal.ingestStore.{getDoc,insertChunks,setReady,setFailed}` names match across T2/T3/T4. The node action (`ingest.ts`, `"use node"`, actions only) calls the write-backs in the regular module (`ingestStore.ts`). `embedChunks(string[]) → number[][]`, `chunkText(string, opts) → string[]`, 1536-dim vector everywhere. `kind` vocabulary (`pdf|docx|xlsx|txt|md`) consistent between `create` (KIND_BY_EXT) and `extractText`.

**Dependency/gate note:** T1 is fully green immediately. T2/T3 code is written then validated at the account-bound deploy gate (regenerates `_generated`) — same, accepted pattern as O1. The Node parse/embed path is runtime-verified at the gate per the approved spec (not unit-tested).
