import { RAG } from "@convex-dev/rag";
import { components } from "./_generated/api";
import type { ActionCtx, MutationCtx } from "./_generated/server";
import { openrouter } from "./openrouter";
import { chunkText } from "./lib/chunk";

// One RAG instance for document context (this task) and chat retrieval
// (Task 2). Namespace == userId for every add/search/delete below, so a
// user's documents are never visible to another user's searches.
export const rag = new RAG(components.rag, {
  textEmbeddingModel: openrouter.embedding("openai/text-embedding-3-large"),
  embeddingDimension: 3072,
});

/**
 * Chunk (via our recursive Arabic-aware splitter) and store `text` under
 * `key` (the documentId) in the user's namespace. `rag.add`'s type only
 * requires `ctx.runMutation`, but it also calls the embedding model over the
 * network, which the Convex mutation runtime forbids — so this must run
 * inside an action. See ingest.ts's "use node" `ingestDocument` action, which
 * already does network I/O for parsing/embeddings.
 */
export async function ragAdd(
  ctx: ActionCtx,
  args: { userId: string; key: string; text: string },
) {
  const chunks = chunkText(args.text);
  const result = await rag.add(ctx, {
    namespace: args.userId,
    key: args.key,
    chunks,
  });
  return { ...result, chunkCount: chunks.length };
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
 * Delete the rag entry stored under `key` (the documentId) in the user's
 * namespace. Only needs `ctx.runQuery`/`ctx.runMutation`, both available on a
 * mutation ctx, so this runs directly inside documents.ts's `remove`
 * mutation — no separate action required.
 */
export async function ragRemove(
  ctx: MutationCtx,
  args: { userId: string; key: string },
) {
  const namespace = await rag.getNamespace(ctx, { namespace: args.userId });
  if (namespace === null) return; // nothing ingested for this user yet
  await rag.deleteByKeyAsync(ctx, {
    namespaceId: namespace.namespaceId,
    key: args.key,
  });
}
