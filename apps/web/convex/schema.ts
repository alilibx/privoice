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
});
