import { query, mutation, internalQuery } from "./_generated/server";
import { v, ConvexError } from "convex/values";
import { getAuthUserId } from "@convex-dev/auth/server";
import type { Doc } from "./_generated/dataModel";

async function requireUserId(ctx: { auth: any; db: any }) {
  const userId = await getAuthUserId(ctx as any);
  if (userId === null) throw new ConvexError("Not authenticated");
  return userId;
}

export const list = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    return await ctx.db
      .query("meetings")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .order("desc")
      .collect();
  },
});

export const create = mutation({
  args: { title: v.string(), notes: v.optional(v.string()) },
  handler: async (ctx, { title, notes }) => {
    const userId = await requireUserId(ctx);
    const clean = title.trim();
    if (clean.length === 0) throw new ConvexError("Title required");
    return await ctx.db.insert("meetings", {
      userId,
      title: clean,
      notes: notes?.trim() || undefined,
      createdAt: Date.now(),
      status: "note",
    });
  },
});

export const remove = mutation({
  args: { id: v.id("meetings") },
  handler: async (ctx, { id }) => {
    const userId = await requireUserId(ctx);
    const row = await ctx.db.get(id);
    if (row === null || row.userId !== userId) {
      throw new ConvexError("Not found"); // don't reveal others' rows
    }
    await ctx.db.delete(id);
  },
});

/**
 * Internal-only: case-insensitive substring search over a single user's
 * meetings (title + notes). `userId` is always supplied by the caller (the
 * searchMeetings agent tool, which resolves it from the authenticated
 * caller's tool ctx — never from client/model input) — this query never
 * derives userId itself, so it stays `by_user`-scoped no matter who calls it.
 */
export const searchByUser = internalQuery({
  args: { userId: v.id("users"), query: v.string() },
  handler: async (ctx, { userId, query }): Promise<Doc<"meetings">[]> => {
    const needle = query.trim().toLowerCase();
    const rows = await ctx.db
      .query("meetings")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .order("desc")
      .collect();
    if (needle.length === 0) return [];
    return rows.filter(
      (row) =>
        row.title.toLowerCase().includes(needle) ||
        (row.notes ?? "").toLowerCase().includes(needle),
    );
  },
});
