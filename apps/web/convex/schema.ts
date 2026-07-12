import { defineSchema, defineTable } from "convex/server";
import { authTables } from "@convex-dev/auth/server";
import { v } from "convex/values";

export default defineSchema({
  ...authTables,
  meetings: defineTable({
    userId: v.id("users"),
    title: v.string(),
    notes: v.optional(v.string()),
    createdAt: v.number(),
    status: v.string(), // "note" in O1 (no audio yet); mirrors mobile status naming
  }).index("by_user", ["userId"]),

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
  // Chunks + embeddings now live in the @convex-dev/rag component (see
  // rag.ts), namespaced per userId — no local vector-index table needed.

  // Side table mapping an @convex-dev/agent threadId (opaque string, owned by
  // the agent component) to the userId that created it. This is our OWN
  // ownership record — independent of the agent component's internals — so
  // listThreads/authorizeThread in chat.ts can enforce per-user isolation
  // with a real, convex-test-testable query, without needing to trust or
  // exercise the agent component's thread metadata.
  chatThreads: defineTable({
    threadId: v.string(),
    userId: v.id("users"),
    title: v.optional(v.string()),
    createdAt: v.number(),
  })
    .index("by_user", ["userId"])
    .index("by_thread", ["threadId"]),

  // Per-user chat-model preference (Task 6). `modelId` is only ever written
  // by settings.ts's `setModel` after validating it against
  // models.shared.ts's MODEL_ALLOWLIST — never trust this column's contents
  // as pre-validated when reading it back (see chat.ts's getUserModel, which
  // re-checks `isAllowedModel` and fails closed to DEFAULT_MODEL).
  userSettings: defineTable({
    userId: v.id("users"),
    modelId: v.string(),
    updatedAt: v.number(),
  }).index("by_user", ["userId"]),

  // Retrieval v2: mirrors chunk text (from documents/meetings) into a Convex
  // full-text-searchable table. This is the BM25 arm of the hybrid pipeline;
  // later tasks fuse these hits with vector search results in candidates.ts.
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
    .index("by_user_sourceId", ["userId", "sourceId"])
    .searchIndex("by_text", {
      searchField: "chunkText",
      filterFields: ["userId", "source"],
    }),
});
