import { RAG } from "@convex-dev/rag";
import { components, internal } from "./_generated/api";
import type { ActionCtx, MutationCtx } from "./_generated/server";
import type { Id } from "./_generated/dataModel";
import { openrouter } from "./openrouter";
import { chunkText } from "./lib/chunk";

// One RAG instance for document context (this task) and chat retrieval
// (Task 2). Namespace == userId for every add/search/delete below, so a
// user's documents are never visible to another user's searches. Every entry
// is tagged with `source`/`sourceId` filters so a later task can scope vector
// search to one source kind (e.g. "document") or a single source id, and so
// deletes can find the right entry by key.
export const rag = new RAG<{ source: string; sourceId: string }>(components.rag, {
  textEmbeddingModel: openrouter.embedding("openai/text-embedding-3-large"),
  embeddingDimension: 3072,
  filterNames: ["source", "sourceId"],
});

/**
 * Chunk (via our recursive Arabic-aware splitter), store in the rag vector
 * store under `key` (the sourceId) in the user's namespace tagged with
 * `source`/`sourceId` filters, and mirror the same chunks into the
 * `knowledgeChunks` BM25 table (see knowledge.ts's `insertChunks`). `rag.add`
 * also calls the embedding model over the network, which the Convex mutation
 * runtime forbids — so this must run inside an action. See ingest.ts's
 * "use node" `ingestDocument` action, which already does network I/O for
 * parsing/embeddings.
 */
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

/**
 * Vector search scoped to one user's namespace. Requires `ctx.runAction`
 * (rag.search calls the component's embed-then-search pipeline), so this
 * must run inside an action — used by Task 2's chat action.
 */
export async function ragSearch(
  ctx: ActionCtx,
  args: { userId: string; query: string; limit?: number },
) {
  return rag.search(ctx, {
    namespace: args.userId,
    query: args.query,
    limit: args.limit ?? 8,
  });
}

/**
 * Delete the rag entry stored under `key` (the sourceId) in the user's
 * namespace, and delete the mirrored `knowledgeChunks` rows for the same
 * (userId, source, sourceId) — see knowledge.ts's `deleteBySource`. Only
 * needs `ctx.runQuery`/`ctx.runMutation`, both available on a mutation ctx,
 * so this runs directly inside documents.ts's `remove` mutation — no
 * separate action required.
 */
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
