import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

// File-storage round-trip: the audio-upload path the web/online tier needs.
// 1) client asks for a short-lived upload URL, 2) POSTs bytes to it,
// 3) Convex returns a storageId, 4) client resolves a served URL to read back.
export const generateUploadUrl = mutation({
  args: {},
  handler: async (ctx) => {
    return await ctx.storage.generateUploadUrl();
  },
});

export const getUrl = query({
  args: { storageId: v.id("_storage") },
  handler: async (ctx, { storageId }) => {
    return await ctx.storage.getUrl(storageId);
  },
});
