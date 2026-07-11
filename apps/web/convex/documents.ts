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
