# Privoice Retrieval v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the vector-only chat retrieval with a deterministic hybrid pipeline (BM25 + vector → fuse → pin/boost → LLM-judge rerank → labeled context pack with citations) over a unified documents+meetings corpus.

**Architecture:** A `convex/retrieval/` module runs a fixed pipeline, exposed through one `searchKnowledge` agent tool (plus a `pinpoint` grep tool). Documents and meetings both embed into the per-user RAG namespace (tagged `source`), and a mirrored `knowledgeChunks` table with a Convex full-text `searchIndex` provides the BM25 arm. The Agent reasons over the pack and cites with `[n]`; the client renders a Sources list from the tool output.

**Tech Stack:** Convex, `@convex-dev/rag` 0.7.5 (`rag.search`, `filterNames`/`filterValues`, `importance`, `chunkContext`, `hybridRank`), `@convex-dev/agent`, `ai` (generateText for rerank), OpenRouter (embeddings + rerank model), Vitest + convex-test, React.

## Global Constraints

- Work in `apps/web/` only. No `apps/mobile`/`packages/*` changes.
- Security: `userId` is server-resolved from `ctx.userId`, never client-supplied; every retrieval + `knowledgeChunks` read is `userId`-scoped. `pinnedSourceIds` validated server-side to belong to the caller. `OPENROUTER_API_KEY` stays server-only.
- Fail-soft: BM25 empty/error → vector-only; vector error → BM25-only; both fail → "no results" (never invent); rerank error/timeout → keep fused order; OpenRouter down → surfaced error, no silent wrong answer.
- Tests runnable from task one: after every task `npx tsc -b`, `npm test`, and (where UI changes) `npm run build` are green. Run `npx convex codegen` after schema/function changes and commit `convex/_generated`.
- Commands run from `apps/web/`; prefix `export PATH="/opt/homebrew/bin:$PATH"` if node isn't found.
- Embedding model: `openrouter.embedding("openai/text-embedding-3-large")`, dim 3072 (unchanged). Namespace = `userId` (unchanged).
- Conventional commits; commit at the end of every task.

## File Structure

```
apps/web/convex/
  retrieval/
    types.ts        # Candidate, SourceRef, RetrievalConfig, RetrievalResult
    config.ts       # RETRIEVAL_CONFIG knobs (server-only)
    candidates.ts   # vectorCandidates() + bm25Candidates()
    fuse.ts         # fuseCandidates() — hybridRank wrapper + fusion key
    pack.ts         # pinAndBoost() + packContext()
    rerank.ts       # rerankCandidates() (LLM-judge, fail-soft)
    retrieve.ts     # retrieve() — orchestrates the pipeline
    *.test.ts       # per-module unit tests + eval.test.ts
  knowledge.ts      # knowledgeChunks: insert/deleteBySource/search (BM25 arm)
  rag.ts            # + filterNames; ragAdd writes mirror + source/sourceId
  ingest.ts         # pass source="document"
  meetings.ts       # + ingestMeeting action + backfill; drop searchByUser
  tools.ts          # searchKnowledge + pinpoint (replace search{Documents,Meetings})
  agent.ts          # tools + instructions (cite with [n])
  chat.ts           # sendMessage gains pinnedSourceIds; writes retrievalPins
  schema.ts         # + knowledgeChunks + retrievalPins
apps/web/src/features/chat/
  Sources.tsx       # renders SourceRef[] under an assistant message
  Markdown.tsx      # linkify [n] markers
  MessageBubble.tsx # render <Sources> from tool-part output
  Chat.tsx          # pass pinnedSourceIds; thread tool sources to bubbles
  ToolTrace.tsx     # label searchKnowledge / pinpoint
```

---

### Task 1: `knowledgeChunks` schema + `knowledge.ts` BM25 arm

**Files:**
- Modify: `apps/web/convex/schema.ts`
- Create: `apps/web/convex/knowledge.ts`
- Test: `apps/web/convex/knowledge.test.ts`

**Interfaces:**
- Produces: table `knowledgeChunks` `{ userId: Id<"users">, entryId: string, source: string, sourceId: string, title: string, chunkText: string, chunkIndex: number }` with `.index("by_user", ["userId"])`, `.index("by_source", ["userId","source","sourceId"])`, `.searchIndex("by_text", { searchField: "chunkText", filterFields: ["userId","source"] })`.
- Produces: `internal.knowledge.insertChunks({ userId, entryId, source, sourceId, title, chunks: string[] })` (internalMutation) → inserts one row per chunk.
- Produces: `internal.knowledge.deleteBySource({ userId, source, sourceId })` (internalMutation).
- Produces: `bm25Search(ctx: QueryCtx, { userId, query, source?, limit }) → Promise<Array<{ entryId, source, sourceId, title, chunkText, chunkIndex }>>` (plain async fn used by candidates.ts).

- [ ] **Step 1: Add the table to `schema.ts`**

Insert into the `defineSchema({...})` object:
```ts
  knowledgeChunks: defineTable({
    userId: v.id("users"),
    entryId: v.string(),
    source: v.string(), // "document" | "meeting"
    sourceId: v.string(),
    title: v.string(),
    chunkText: v.string(),
    chunkIndex: v.number(),
  })
    .index("by_user", ["userId"])
    .index("by_source", ["userId", "source", "sourceId"])
    .searchIndex("by_text", {
      searchField: "chunkText",
      filterFields: ["userId", "source"],
    }),
```
Run `npx convex codegen`.

- [ ] **Step 2: Write the failing test**

`apps/web/convex/knowledge.test.ts`:
```ts
import { convexTest } from "convex-test";
import { expect, test } from "vitest";
import schema from "./schema";
import { internal } from "./_generated/api";
import { bm25Search } from "./knowledge";

test("insert then bm25 search returns matching chunks, delete removes them", async () => {
  const t = convexTest(schema);
  const userId = await t.run(async (ctx) =>
    ctx.db.insert("users", {} as any),
  );
  await t.mutation(internal.knowledge.insertChunks, {
    userId,
    entryId: "e1",
    source: "document",
    sourceId: "d1",
    title: "Q3 report",
    chunks: ["Revenue grew twelve percent this quarter", "Costs held flat"],
  });

  const hits = await t.run((ctx) =>
    bm25Search(ctx, { userId, query: "revenue", limit: 10 }),
  );
  expect(hits.length).toBeGreaterThan(0);
  expect(hits[0].sourceId).toBe("d1");
  expect(hits[0].chunkText).toMatch(/revenue/i);

  await t.mutation(internal.knowledge.deleteBySource, {
    userId,
    source: "document",
    sourceId: "d1",
  });
  const after = await t.run((ctx) =>
    bm25Search(ctx, { userId, query: "revenue", limit: 10 }),
  );
  expect(after).toHaveLength(0);
});
```

- [ ] **Step 3: Run — expect FAIL** (`knowledge` module not found).
Run: `npx vitest run convex/knowledge.test.ts`

- [ ] **Step 4: Implement `knowledge.ts`**
```ts
import { v } from "convex/values";
import { internalMutation, type QueryCtx } from "./_generated/server";
import type { Id } from "./_generated/dataModel";

export const insertChunks = internalMutation({
  args: {
    userId: v.id("users"),
    entryId: v.string(),
    source: v.string(),
    sourceId: v.string(),
    title: v.string(),
    chunks: v.array(v.string()),
  },
  handler: async (ctx, { userId, entryId, source, sourceId, title, chunks }) => {
    for (let i = 0; i < chunks.length; i++) {
      await ctx.db.insert("knowledgeChunks", {
        userId, entryId, source, sourceId, title,
        chunkText: chunks[i], chunkIndex: i,
      });
    }
  },
});

export const deleteBySource = internalMutation({
  args: { userId: v.id("users"), source: v.string(), sourceId: v.string() },
  handler: async (ctx, { userId, source, sourceId }) => {
    const rows = await ctx.db
      .query("knowledgeChunks")
      .withIndex("by_source", (q) =>
        q.eq("userId", userId).eq("source", source).eq("sourceId", sourceId),
      )
      .collect();
    for (const row of rows) await ctx.db.delete(row._id);
  },
});

export type Bm25Hit = {
  entryId: string; source: string; sourceId: string;
  title: string; chunkText: string; chunkIndex: number;
};

export async function bm25Search(
  ctx: QueryCtx,
  args: { userId: Id<"users">; query: string; source?: string; limit: number },
): Promise<Bm25Hit[]> {
  const q = args.query.trim();
  if (q.length === 0) return [];
  const rows = await ctx.db
    .query("knowledgeChunks")
    .withSearchIndex("by_text", (s) => {
      let b = s.search("chunkText", q).eq("userId", args.userId);
      if (args.source) b = b.eq("source", args.source);
      return b;
    })
    .take(args.limit);
  return rows.map((r) => ({
    entryId: r.entryId, source: r.source, sourceId: r.sourceId,
    title: r.title, chunkText: r.chunkText, chunkIndex: r.chunkIndex,
  }));
}
```
Run `npx convex codegen`.

- [ ] **Step 5: Run — expect PASS.** `npx vitest run convex/knowledge.test.ts`

- [ ] **Step 6: Commit**
```bash
git add apps/web/convex/schema.ts apps/web/convex/knowledge.ts apps/web/convex/knowledge.test.ts apps/web/convex/_generated
git commit -m "feat(web): knowledgeChunks table + BM25 search arm (retrieval v2)"
```

---

### Task 2: RAG `filterNames` + `ragAdd` writes the mirror + document ingest tagging

**Files:**
- Modify: `apps/web/convex/rag.ts`, `apps/web/convex/ingest.ts`, `apps/web/convex/documents.ts`
- Test: `apps/web/convex/documents.test.ts` (extend existing)

**Interfaces:**
- Consumes: `internal.knowledge.insertChunks`, `internal.knowledge.deleteBySource` (Task 1).
- Produces: `ragAdd(ctx: ActionCtx, { userId, source, sourceId, title, text }) → { chunkCount }` — chunks, `rag.add` with `filterValues [{name:"source",value:source},{name:"sourceId",value:sourceId}]` + `metadata:{ title, source, sourceId }`, then `runMutation(insertChunks)` with the same chunks and the returned `entryId`.
- Produces: `ragRemoveSource(ctx: MutationCtx, { userId, source, sourceId })` — removes the rag entry (key = sourceId) AND `deleteBySource`.

- [ ] **Step 1: Reconstruct `rag` with filters + rewrite `ragAdd`/removal in `rag.ts`**

Change the `new RAG(...)`:
```ts
export const rag = new RAG<{ source: string; sourceId: string }>(components.rag, {
  textEmbeddingModel: openrouter.embedding("openai/text-embedding-3-large"),
  embeddingDimension: 3072,
  filterNames: ["source", "sourceId"],
});
```
Replace `ragAdd` (keep `chunkText` splitter):
```ts
export async function ragAdd(
  ctx: ActionCtx,
  args: { userId: string; source: string; sourceId: string; title: string; text: string },
) {
  const chunks = chunkText(args.text);
  const { entryId } = await rag.add(ctx, {
    namespace: args.userId,
    key: args.sourceId,
    title: args.title,
    chunks,
    filterValues: [
      { name: "source", value: args.source },
      { name: "sourceId", value: args.sourceId },
    ],
    metadata: { title: args.title, source: args.source, sourceId: args.sourceId },
  });
  await ctx.runMutation(internal.knowledge.insertChunks, {
    userId: args.userId as Id<"users">,
    entryId: String(entryId),
    source: args.source,
    sourceId: args.sourceId,
    title: args.title,
    chunks,
  });
  return { entryId: String(entryId), chunkCount: chunks.length };
}
```
Add imports: `import { internal } from "./_generated/api";` and `import type { Id } from "./_generated/dataModel";`. Keep `ragSearch` for now (Task 3 replaces its callers; delete in Task 7). Replace `ragRemove` with `ragRemoveSource` that also deletes the mirror:
```ts
export async function ragRemoveSource(
  ctx: MutationCtx,
  args: { userId: string; source: string; sourceId: string },
) {
  const namespace = await rag.getNamespace(ctx, { namespace: args.userId });
  if (namespace !== null) {
    await rag.deleteByKeyAsync(ctx, { namespaceId: namespace.namespaceId, key: args.sourceId });
  }
  await ctx.runMutation(internal.knowledge.deleteBySource, {
    userId: args.userId as Id<"users">,
    source: args.source,
    sourceId: args.sourceId,
  });
}
```

> NOTE for implementer: confirm `rag.add` returns `{ entryId }` and accepts `title`/`filterValues`/`metadata` against `node_modules/@convex-dev/rag/dist/client/*.d.ts`. If `entryId` isn't returned by `add`, look it up via the `key` (sourceId) using the component's entry lookup and store that. Adapt names to the installed types; do not invent fields.

- [ ] **Step 2: Update `ingest.ts`** — change the `ragAdd` call to pass source/title:
```ts
const { chunkCount } = await ragAdd(ctx, {
  userId: doc.userId, source: "document", sourceId: documentId,
  title: doc.filename, text,
});
```

- [ ] **Step 3: Update `documents.ts` `remove`** — replace `ragRemove(...)` with:
```ts
await ragRemoveSource(ctx, { userId, source: "document", sourceId: id });
```
(Import `ragRemoveSource` instead of `ragRemove`.)

- [ ] **Step 4: Extend `documents.test.ts`** — its existing `./rag` mock must now mock `ragAdd`/`ragRemoveSource`. Add a case asserting that after a mocked ingest, `knowledgeChunks` rows exist for the doc, and after `remove` they're gone. (Read the current mock; keep its shape, add `ragRemoveSource`.) Provide the mock:
```ts
vi.mock("./rag", () => ({
  ragAdd: vi.fn(async () => ({ entryId: "e1", chunkCount: 2 })),
  ragRemoveSource: vi.fn(async () => {}),
}));
```
Keep existing document CRUD assertions passing.

- [ ] **Step 5: Run — `npx tsc -b && npx vitest run convex/documents.test.ts`** — expect PASS. Then `npx convex codegen`.

- [ ] **Step 6: Commit**
```bash
git add apps/web/convex/rag.ts apps/web/convex/ingest.ts apps/web/convex/documents.ts apps/web/convex/documents.test.ts apps/web/convex/_generated
git commit -m "feat(web): tag rag entries with source/sourceId + mirror chunks for BM25"
```

---

### Task 3: retrieval types/config + candidates + fusion key

**Files:**
- Create: `apps/web/convex/retrieval/{types.ts,config.ts,candidates.ts,fuse.ts}`
- Test: `apps/web/convex/retrieval/fuse.test.ts`

**Interfaces:**
- Produces `types.ts`:
```ts
export type Candidate = {
  key: string;        // fusion key (see fuse.ts)
  entryId: string;
  source: string;     // "document" | "meeting"
  sourceId: string;
  title: string;
  text: string;
  score: number;      // arm-native score (cosine or bm25 rank proxy)
};
export type SourceRef = { n: number; source: string; sourceId: string; title: string; locator: string };
export type RetrievalConfig = {
  candidateK: number; fuseWeights: [number, number]; rrfK: number;
  chunkContext: { before: number; after: number }; vectorScoreThreshold: number;
  rerankEnabled: boolean; rerankModel: string; rerankPool: number; keepN: number; tokenBudget: number;
};
export type RetrievalResult = { pack: string; sources: SourceRef[] };
```
- Produces `config.ts`: `export const RETRIEVAL_CONFIG: RetrievalConfig = { candidateK: 20, fuseWeights: [1,1], rrfK: 10, chunkContext: { before: 1, after: 1 }, vectorScoreThreshold: 0.2, rerankEnabled: true, rerankModel: "openai/gpt-4o-mini", rerankPool: 30, keepN: 8, tokenBudget: 6000 };`
- Produces `candidates.ts`: `vectorCandidates(ctx, { userId, query, source?, cfg }) → Promise<Candidate[]>` (via `rag.search`) and `bm25Candidates(ctx, { userId, query, source?, cfg }) → Promise<Candidate[]>` (via `knowledge.bm25Search`, run through `ctx.runQuery` since it needs a query ctx from an action).
- Produces `fuse.ts`: `fuseCandidates(bm25: Candidate[], vector: Candidate[], cfg) → Candidate[]` — dedupe by `key`, order by `hybridRank([bm25keys, vectorkeys], { weights: cfg.fuseWeights, k: cfg.rrfK })`.

- [ ] **Step 1: Fusion-key gate.** Inspect `rag.search`'s result item shape: `grep -rE "vSearchResult|order|entryId|startOrder|content|text" node_modules/@convex-dev/rag/dist/shared.d.ts node_modules/@convex-dev/rag/dist/client/index.d.ts`. Decide the shared `key`:
  - If a result item exposes a stable per-chunk identity together with `entryId` and a chunk order/index → `key = \`${entryId}:${order}\`` and set the same on BM25 candidates (`\`${entryId}:${chunkIndex}\``).
  - Otherwise (committed default) → **entry-level**: `key = entryId`; when mapping, keep the highest-scoring chunk per `entryId` as that entry's representative Candidate.
  Record the choice in a comment at the top of `fuse.ts`.

- [ ] **Step 2: Write the failing test** (`fuse.test.ts`) — deterministic, no ctx:
```ts
import { expect, test } from "vitest";
import { fuseCandidates } from "./fuse";
import { RETRIEVAL_CONFIG } from "./config";
import type { Candidate } from "./types";

const c = (key: string, score = 1): Candidate => ({
  key, entryId: key, source: "document", sourceId: key, title: key, text: key, score,
});

test("fusion favors items ranked highly in both arms", () => {
  const bm25 = [c("a"), c("b"), c("c")];
  const vector = [c("b"), c("c"), c("a")];
  const fused = fuseCandidates(bm25, vector, RETRIEVAL_CONFIG);
  expect(fused.map((x) => x.key)).toEqual(["b", "a", "c"]);
});

test("dedupes items present in both arms", () => {
  const fused = fuseCandidates([c("a"), c("b")], [c("a")], RETRIEVAL_CONFIG);
  expect(fused.filter((x) => x.key === "a")).toHaveLength(1);
});
```
(The exact expected order for test 1 follows RRF with k=10; if the implementation yields a different valid RRF order, adjust the expectation to the computed order — but the property "b first, all three present, deduped" must hold.)

- [ ] **Step 3: Run — expect FAIL.** `npx vitest run convex/retrieval/fuse.test.ts`

- [ ] **Step 4: Implement `types.ts`, `config.ts`, `fuse.ts`, `candidates.ts`.**
`fuse.ts`:
```ts
import { hybridRank } from "@convex-dev/rag";
import type { Candidate, RetrievalConfig } from "./types";

export function fuseCandidates(
  bm25: Candidate[], vector: Candidate[], cfg: RetrievalConfig,
): Candidate[] {
  const byKey = new Map<string, Candidate>();
  for (const cand of [...vector, ...bm25]) if (!byKey.has(cand.key)) byKey.set(cand.key, cand);
  const order = hybridRank([bm25.map((c) => c.key), vector.map((c) => c.key)], {
    weights: cfg.fuseWeights, k: cfg.rrfK,
  });
  return order.map((k) => byKey.get(k)!).filter(Boolean);
}
```
`candidates.ts` uses `rag.search` (vector) and routes BM25 through an internal query wrapper (add `internal.knowledge.searchQuery` internalQuery that calls `bm25Search`, since actions can't touch `ctx.db` directly). Map both to `Candidate` using the Step-1 key rule. Vector `text` comes from the result content; `score` from the result score; `entryId`/metadata from the result. (Adapt field names to the verified shape.)

- [ ] **Step 5: Run — expect PASS.** `npx vitest run convex/retrieval/fuse.test.ts` and `npx tsc -b`.

- [ ] **Step 6: Commit**
```bash
git add apps/web/convex/retrieval apps/web/convex/knowledge.ts apps/web/convex/_generated
git commit -m "feat(web): retrieval candidates + hybridRank fusion (verified fusion key)"
```

---

### Task 4: pin/boost + context pack

**Files:**
- Modify: `apps/web/convex/retrieval/pack.ts` (create)
- Test: `apps/web/convex/retrieval/pack.test.ts`

**Interfaces:**
- Produces: `pinAndBoost(fused: Candidate[], pinnedSourceIds: string[]) → Candidate[]` — stable-partition so candidates whose `sourceId ∈ pinnedSourceIds` come first (order preserved within each group); all candidates retained.
- Produces: `packContext(kept: Candidate[], cfg) → RetrievalResult` — number `[1..n]`, build `pack` string (route header + `"[n] <title> — <locator>\n<text>"` best-first, truncated to ~`cfg.tokenBudget` via a chars≈tokens*4 heuristic) and `sources: SourceRef[]`. `locator` = `source==="meeting" ? "meeting" : "document"` for now (chunkIndex appended, e.g. `"§2"`).

- [ ] **Step 1: Write failing tests** (`pack.test.ts`):
```ts
import { expect, test } from "vitest";
import { pinAndBoost, packContext } from "./pack";
import { RETRIEVAL_CONFIG } from "./config";
import type { Candidate } from "./types";
const c = (sourceId: string): Candidate => ({
  key: sourceId, entryId: sourceId, source: "document", sourceId,
  title: `T-${sourceId}`, text: `body ${sourceId}`, score: 1,
});

test("pinned sources move to the front, none dropped", () => {
  const out = pinAndBoost([c("a"), c("b"), c("c")], ["c"]);
  expect(out.map((x) => x.sourceId)).toEqual(["c", "a", "b"]);
  expect(out).toHaveLength(3);
});

test("pack numbers sources and returns matching SourceRefs", () => {
  const { pack, sources } = packContext([c("a"), c("b")], RETRIEVAL_CONFIG);
  expect(pack).toContain("[1]");
  expect(pack).toContain("[2]");
  expect(pack).toContain("T-a");
  expect(sources).toHaveLength(2);
  expect(sources[0]).toMatchObject({ n: 1, sourceId: "a", title: "T-a" });
});
```

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement `pack.ts`** (pinAndBoost = stable partition; packContext = numbering + budget loop).
- [ ] **Step 4: Run — expect PASS.**
- [ ] **Step 5: Commit** `feat(web): retrieval pin/boost + labeled context pack with citations`

---

### Task 5: LLM-judge rerank (fail-soft)

**Files:**
- Create: `apps/web/convex/retrieval/rerank.ts`, `apps/web/convex/retrieval/rerank.test.ts`

**Interfaces:**
- Produces: `rerankCandidates(fused: Candidate[], query: string, cfg, deps?: { generate?: GenerateFn }) → Promise<Candidate[]>` — takes the top `cfg.rerankPool`, asks the model to return the best `cfg.keepN` 0-based indices as JSON `{ "keep": number[] }`, returns those candidates in that order. On any throw / unparseable output → returns `fused.slice(0, cfg.keepN)`. `GenerateFn = (args: { model: string; prompt: string }) => Promise<string>`; default calls `generateText` from `ai` with `openrouter.chat(cfg.rerankModel)`. Injecting `deps.generate` keeps it unit-testable offline.

- [ ] **Step 1: Write failing tests** injecting a fake generate:
```ts
import { expect, test } from "vitest";
import { rerankCandidates } from "./rerank";
import { RETRIEVAL_CONFIG } from "./config";
import type { Candidate } from "./types";
const cfg = { ...RETRIEVAL_CONFIG, keepN: 2, rerankPool: 5 };
const cand = (k: string): Candidate => ({ key: k, entryId: k, source: "document", sourceId: k, title: k, text: k, score: 1 });

test("keeps and orders by the model's chosen indices", async () => {
  const fused = [cand("a"), cand("b"), cand("c")];
  const out = await rerankCandidates(fused, "q", cfg, {
    generate: async () => JSON.stringify({ keep: [2, 0] }),
  });
  expect(out.map((x) => x.key)).toEqual(["c", "a"]);
});

test("fails soft to fused top-N on bad output", async () => {
  const fused = [cand("a"), cand("b"), cand("c")];
  const out = await rerankCandidates(fused, "q", cfg, {
    generate: async () => "not json",
  });
  expect(out.map((x) => x.key)).toEqual(["a", "b"]);
});

test("fails soft on thrown error", async () => {
  const fused = [cand("a"), cand("b"), cand("c")];
  const out = await rerankCandidates(fused, "q", cfg, {
    generate: async () => { throw new Error("timeout"); },
  });
  expect(out.map((x) => x.key)).toEqual(["a", "b"]);
});
```

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement `rerank.ts`** — build a numbered-candidate prompt ("Return JSON {\"keep\":[indices]} of the up-to-N most relevant to the query, best first"), parse defensively (`JSON.parse`, validate array of in-range ints), clamp to `keepN`. Default `generate` uses `generateText({ model: openrouter.chat(cfg.rerankModel), prompt }).then(r => r.text)`.
- [ ] **Step 4: Run — expect PASS.**
- [ ] **Step 5: Commit** `feat(web): LLM-judge rerank stage (fail-soft, injectable)`

---

### Task 6: `retrieve()` orchestration

**Files:**
- Create: `apps/web/convex/retrieval/retrieve.ts`, `apps/web/convex/retrieval/retrieve.test.ts`

**Interfaces:**
- Consumes: candidates, fuse, pinAndBoost, packContext, rerank.
- Produces: `retrieve(ctx: ActionCtx, { userId, query, source?, pinnedSourceIds, cfg? }) → Promise<RetrievalResult>` — runs vector+BM25 (fail-soft per arm), `fuseCandidates`, `pinAndBoost`, `rerankCandidates` (if `cfg.rerankEnabled`), `packContext`. Empty candidates → `{ pack: "No matching documents or meetings.", sources: [] }`.

- [ ] **Step 1: Write failing test** by injecting stubbed stage deps (retrieve accepts an optional `deps` with `vector`, `bm25`, `rerank` overrides for testing) so no ctx/network is needed:
```ts
import { expect, test } from "vitest";
import { retrieve } from "./retrieve";
import type { Candidate } from "./types";
const c = (k: string): Candidate => ({ key: k, entryId: k, source: "document", sourceId: k, title: k, text: k, score: 1 });

test("pipeline returns a pack + sources, pinned first", async () => {
  const res = await retrieve({} as any, {
    userId: "u1", query: "revenue", pinnedSourceIds: ["b"],
    deps: {
      vector: async () => [c("a"), c("b")],
      bm25: async () => [c("b"), c("c")],
      rerank: async (cands) => cands.slice(0, 8),
    },
  });
  expect(res.sources[0].sourceId).toBe("b"); // pinned to front
  expect(res.pack).toContain("[1]");
});

test("no candidates yields an explicit empty result", async () => {
  const res = await retrieve({} as any, {
    userId: "u1", query: "x", pinnedSourceIds: [],
    deps: { vector: async () => [], bm25: async () => [], rerank: async (c) => c },
  });
  expect(res.sources).toHaveLength(0);
  expect(res.pack).toMatch(/no matching/i);
});
```

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement `retrieve.ts`** — default `deps` wire to `vectorCandidates`/`bm25Candidates`/`rerankCandidates`; wrap each arm in try/catch (log + return []); if both arms empty → empty result.
- [ ] **Step 4: Run — expect PASS + `npx tsc -b`.**
- [ ] **Step 5: Commit** `feat(web): retrieve() pipeline orchestration (fail-soft arms)`

---

### Task 7: Tools — `searchKnowledge` + `pinpoint`; agent instructions

**Files:**
- Modify: `apps/web/convex/tools.ts`, `apps/web/convex/agent.ts`, `apps/web/convex/rag.ts` (delete `ragSearch`)
- Rewrite: `apps/web/convex/tools.test.ts`
- Create: `internal.retrieval.run` action wrapper (in `retrieve.ts` or a thin `convex/retrieval/api.ts`) so the tool can call `retrieve` (which needs an ActionCtx) — the tool `execute` already runs in an action ctx, so it can call `retrieve(ctx, …)` directly; no wrapper needed if types allow. Verify and adapt.

**Interfaces:**
- Produces: `searchKnowledge` tool — `inputSchema z.object({ query: z.string(), source: z.enum(["document","meeting"]).optional() })`. Resolves `userId` (fail-closed), reads the caller's pins via `internal.chat.getPins` (Task 9), calls `retrieve`, returns a string: `pack + "\n\n<<<SOURCES>>>\n" + JSON.stringify(sources)`. The Agent reads `pack`; the client parses the `<<<SOURCES>>>` block from the tool part output.
- Produces: `pinpoint` tool — `inputSchema z.object({ sourceId: z.string(), pattern: z.string() })`. Reads that source's mirror rows (`internal.knowledge.linesFor`), regex-matches `pattern`, returns matching lines with ±2 lines context, scoped to `ctx.userId`.

- [ ] **Step 1: Rewrite `tools.test.ts`** for the new tools' security contract (userId from ctx, fail-closed), mocking `./retrieve` and the ctx.runQuery for pins. Keep the two security properties (scopes to ctx.userId; throws with no userId) for `searchKnowledge`; add one for `pinpoint`. (Mirror the existing test's `withCtx`/`execute` invocation pattern.)
- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement `searchKnowledge` + `pinpoint` in `tools.ts`**; delete `searchDocuments`/`searchMeetings`. Add `internal.knowledge.linesFor` (internalQuery returning the concatenated chunk text for a `sourceId`, userId-scoped).
- [ ] **Step 4: Update `agent.ts`** — `tools: { searchKnowledge, pinpoint }`; instructions append: `"Use searchKnowledge for questions about the user's documents or meetings; use pinpoint to find exact values (dates, amounts, clause numbers) within a known source. Ground every claim in the returned context and cite with [n] matching the numbered sources. Never cite a source that wasn't provided; if the context is insufficient, say so."` Keep `stopWhen: stepCountIs(5)`.
- [ ] **Step 5: Delete `ragSearch` from `rag.ts`** (no remaining callers).
- [ ] **Step 6: Run — `npx tsc -b && npx vitest run convex/tools.test.ts`** — expect PASS. `npx convex codegen`.
- [ ] **Step 7: Commit** `feat(web): searchKnowledge + pinpoint tools; cite-with-[n] agent instructions`

---

### Task 8: Meeting ingestion + backfill; drop `searchByUser`

**Files:**
- Modify: `apps/web/convex/meetings.ts`, `apps/web/convex/meetings.test.ts`
- Create: `internal.meetings.ingestMeeting` (action), `internal.meetings.backfill` (action)

**Interfaces:**
- Produces: `ingestMeeting(ctx, { meetingId })` — reads the meeting, builds `text = [title, notes, transcript].filter(Boolean).join("\n\n")`, calls `ragAdd(ctx, { userId, source: "meeting", sourceId: meetingId, title, text })`. Scheduled from `create` and from any future notes/transcript update.
- Produces: `backfill(ctx)` — iterate all meetings, schedule `ingestMeeting` for each (idempotent: `rag.add` keyed by meetingId replaces).
- `meetings.remove` also calls `ragRemoveSource(ctx, { userId, source: "meeting", sourceId: id })`.
- Deletes `searchByUser` (no callers after Task 7).

- [ ] **Step 1: Update `meetings.test.ts`** — remove `searchByUser` cases; add a case asserting `create` schedules ingestion (mock scheduler) and `remove` calls `ragRemoveSource` (mock `./rag`). Keep list/create/remove assertions.
- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement** `ingestMeeting` (a `"use node"`? — `ragAdd` calls embeddings, so it must be an action; meetings ingestion has no doc parsing, so a normal `internalAction` suffices, no `"use node"`). Schedule from `create` via `ctx.scheduler.runAfter(0, internal.meetings.ingestMeeting, { meetingId })`. Add `backfill`. Add `ragRemoveSource` to `remove`. Delete `searchByUser`.
- [ ] **Step 4: Run — `npx tsc -b && npx vitest run convex/meetings.test.ts`** — expect PASS. `npx convex codegen`.
- [ ] **Step 5: Commit** `feat(web): ingest meetings into the unified corpus + backfill; drop title-only search`

---

### Task 9: `pinnedSourceIds` through `sendMessage`

**Files:**
- Modify: `apps/web/convex/schema.ts` (+`retrievalPins`), `apps/web/convex/chat.ts`, `apps/web/src/features/chat/Chat.tsx`
- Test: `apps/web/convex/chat.test.ts` (extend)

**Interfaces:**
- Produces: table `retrievalPins` `{ userId, sourceIds: string[], updatedAt }` index `by_user`.
- Produces: `internal.chat.getPins({ userId }) → string[]` (internalQuery; used by `searchKnowledge`).
- Modifies: `sendMessage` args add `pinnedSourceIds: v.optional(v.array(v.string()))`; before `streamText`, validate each id belongs to the caller (owns the `documents`/`meetings` row) and upsert `retrievalPins`; after `consumeStream`, clear them.
- Modifies: `Chat.tsx` `handleSend` passes `pinnedSourceIds: atts.map(a => a.docId)` to `sendMessage`.

- [ ] **Step 1: Add table + getPins; extend `chat.test.ts`** to assert `getPins` returns only ids the user owns after a `sendMessage` with `pinnedSourceIds` (the existing chat tests mock generation, so assert the validation/upsert path via a direct call or a small internal helper). Write the failing test.
- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement** schema table, `getPins`, `sendMessage` validation+upsert+clear, `searchKnowledge` reads pins via `internal.chat.getPins`. `Chat.tsx` passes the ids.
- [ ] **Step 4: Run — `npx tsc -b && npm test`** — expect PASS. `npx convex codegen`.
- [ ] **Step 5: Commit** `feat(web): per-turn attachment pinning via validated pinnedSourceIds`

---

### Task 10: Citations UI — Sources list + `[n]` linkify

**Files:**
- Create: `apps/web/src/features/chat/Sources.tsx`, `apps/web/src/test/Sources.test.tsx`
- Modify: `apps/web/src/features/chat/{MessageBubble.tsx,Markdown.tsx,Chat.tsx,ToolTrace.tsx}`, `apps/web/src/test/{Chat.test.tsx,ToolTrace.test.tsx}`

**Interfaces:**
- Produces: `type SourceRef = { n:number; source:string; sourceId:string; title:string; locator:string }` (client copy); `parseSources(toolOutput: string): SourceRef[]` — extracts JSON after `<<<SOURCES>>>`.
- Produces: `<Sources sources={SourceRef[]} />` — a compact "Sources" list under an assistant message.
- `MessageBubble` extracts sources from the assistant message's `tool-searchKnowledge` part output and renders `<Sources>` below the text.
- `Markdown` renders `[n]` as a small superscript reference.

- [ ] **Step 1: Write failing tests** — `Sources.test.tsx` (renders titles + numbers); update `ToolTrace.test.tsx` label expectation to `/searched your knowledge/i` (see Step 4). `parseSources` unit test (valid + missing block → []).
- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement `Sources.tsx` + `parseSources`; wire `MessageBubble`** to find the `searchKnowledge` tool part, `parseSources(part.output)`, render `<Sources>`.
- [ ] **Step 4: Update `ToolTrace.tsx` label map** — add `"tool-searchKnowledge": "Searched your knowledge"`, `"tool-pinpoint": "Pinpointed exact matches"`. Update `Chat.test.tsx`/`ToolTrace.test.tsx` fixtures from `tool-searchDocuments` to `tool-searchKnowledge` and the asserted label to `/searched your knowledge/i`.
- [ ] **Step 5: `Markdown.tsx`** — add a lightweight `[n]` → `<sup>` transform (regex in a `text`-node renderer or a pre-pass) that doesn't break normal text.
- [ ] **Step 6: Run — `npx tsc -b && npm test && npm run build`** — expect PASS.
- [ ] **Step 7: Commit** `feat(web): inline [n] citations + Sources list under assistant answers`

---

### Task 11: Retrieval eval harness

**Files:**
- Create: `apps/web/convex/retrieval/eval.test.ts`

**Interfaces:** consumes the full pipeline via convex-test with a **stubbed embedding model** (deterministic, offline) and rerank bypassed (`cfg.rerankEnabled = false`).

- [ ] **Step 1: Write the eval** — seed a fixed corpus (2 documents + 2 meetings) into a user's namespace through the real ingest path with a stub embedding (mock `openrouter.embedding` to a deterministic hash→vector, or mock `rag.search` to score by keyword overlap so BM25+fusion are exercised for real; prefer stubbing the embedding so `rag` is real). Then run a fixtures array:
```ts
const FIXTURES = [
  { query: "revenue growth", expect: "doc-finance" },
  { query: "action items from standup", expect: "meeting-standup" },
];
```
Assert for each: the expected `sourceId` appears in `result.sources`. Assert citation-correctness: every `sources[i].sourceId` is one of the seeded ids. Assert the **attachment golden**: with `pinnedSourceIds:["doc-new"]` and a vague query "what is this", `sources[0].sourceId === "doc-new"`.
- [ ] **Step 2: Run — iterate until green.** `npx vitest run convex/retrieval/eval.test.ts`
- [ ] **Step 3: Commit** `test(web): retrieval eval harness — recall@k, citation-correctness, attachment golden`

---

### Task 12: Verification + STATUS.md

- [ ] **Step 1: Orphan check** — `grep -rn "searchDocuments\|searchMeetings\|ragSearch\|searchByUser\|ragRemove\b" apps/web/{convex,src}` returns nothing.
- [ ] **Step 2: Full gate** — from `apps/web`: `npx convex codegen && npx tsc -b && npm test && npm run build`. Expect: codegen clean, tsc clean, all suites pass, build succeeds. From repo root: `melos run analyze` clean.
- [ ] **Step 3: Live smoke (manual, user-driven)** — `npx convex dev` (runs the meeting backfill once via `npx convex run meetings:backfill` if exposed), then in the app: upload a doc in chat + "what is this" grounds on it with a Sources list; "compare my doc to my meeting notes" pulls from both; a keyword-exact query (an amount/date) surfaces the right passage; citations render and link.
- [ ] **Step 4: Update STATUS.md** — add **C4 — Retrieval v2** ✅ under the Privoice Cloud workstream (hybrid + rerank + pinning + citations, unified corpus); note the eval harness. Mark ✅ only after Steps 2–3 pass.
- [ ] **Step 5: Commit** `docs(status): retrieval v2 (C4) complete + verified`

---

## Self-Review

**Spec coverage:**
- Unified corpus (docs + meetings, `source` filter) → Tasks 2, 8 ✅
- BM25 arm via `knowledgeChunks` + `searchIndex` → Task 1 ✅
- Fusion key gate (chunk vs entry default) → Task 3 Step 1 ✅
- Pipeline: candidates → fuse → pin/boost → rerank → pack → Tasks 3–6 ✅
- Pinning (inclusive, validated) → Tasks 4 (boost), 9 (pins plumbing) ✅
- LLM-judge rerank, fail-soft, config-gated → Task 5, config in Task 3 ✅
- Tools `searchKnowledge` + `pinpoint`; agent cite-with-[n] → Task 7 ✅
- Citations: tool `sources[]` → client Sources list + `[n]` → Task 10 ✅
- Grep/pinpoint → Task 7 (`pinpoint`) ✅
- Eval harness (recall@k, citation-correctness, attachment golden) → Task 11 ✅
- Fail-soft everywhere → Tasks 5, 6, 7 ✅
- Security (userId server-side, pins validated, key server-only) → Tasks 7, 9, Global Constraints ✅
- STATUS.md C4 → Task 12 ✅

**Placeholder scan:** The two component-API unknowns (`rag.add` return shape in Task 2; `rag.search` result shape in Task 3) are explicit *verify-then-adapt* steps with committed fallbacks (look up entry by key; entry-level fusion) — not deferred work. All test steps contain real code.

**Type consistency:** `Candidate`/`SourceRef`/`RetrievalConfig`/`RetrievalResult` defined in Task 3 `types.ts` and used unchanged in Tasks 4–7, 10. `ragAdd` signature (`{userId,source,sourceId,title,text}`) consistent across Tasks 2, 8. `retrieve(ctx,{userId,query,source?,pinnedSourceIds,cfg?,deps?})` consistent between Task 6 and its Task 7 caller. `bm25Search`/`insertChunks`/`deleteBySource` names consistent Tasks 1–3, 8. Tool part type `tool-searchKnowledge` consistent Tasks 7, 10.
