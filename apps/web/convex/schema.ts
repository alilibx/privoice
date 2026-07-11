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
});
