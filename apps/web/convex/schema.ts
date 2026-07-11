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
});
