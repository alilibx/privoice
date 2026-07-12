import { query, mutation, internalQuery, internalAction } from "./_generated/server";
import { v, ConvexError } from "convex/values";
import { getAuthUserId } from "@convex-dev/auth/server";
import { internal } from "./_generated/api";
import { ragAdd, ragRemoveSource } from "./rag";

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
    const id = await ctx.db.insert("meetings", {
      userId,
      title: clean,
      notes: notes?.trim() || undefined,
      createdAt: Date.now(),
      status: "note",
    });
    // Ingest into the unified RAG + BM25 corpus so searchKnowledge covers
    // this meeting alongside documents — see ingestMeeting below.
    await ctx.scheduler.runAfter(0, internal.meetings.ingestMeeting, { meetingId: id });
    return id;
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
    // meetingId is the rag key within this user's namespace — see ragAdd in
    // ingestMeeting below, which stores under the same (userId, meetingId)
    // pair. Clean corpus refs before deleting the row, matching documents.ts.
    await ragRemoveSource(ctx, { userId, source: "meeting", sourceId: id });
    await ctx.db.delete(id);
  },
});

/**
 * Internal-only: read a single meeting row for ingestMeeting. Actions can't
 * touch ctx.db directly, so ingestMeeting reads through this query.
 */
export const getForIngest = internalQuery({
  args: { meetingId: v.id("meetings") },
  handler: async (ctx, { meetingId }) => await ctx.db.get(meetingId),
});

/**
 * Internal-only: every meeting row, for `backfill` to re-ingest. A full
 * table scan is acceptable here — this backs an internal maintenance
 * action, not a user-facing query.
 */
export const allMeetings = internalQuery({
  args: {},
  handler: async (ctx) => await ctx.db.query("meetings").collect(),
});

/**
 * Ingest a meeting into the unified RAG + BM25 corpus so `searchKnowledge`
 * covers meetings alongside documents. The `meetings` table has no
 * transcript field yet (mobile hasn't synced audio/transcripts up) — once
 * one exists, fold it into `text` here alongside title/notes. `ragAdd` calls
 * embeddings over the network, so this must be an action; unlike
 * ingest.ts's documents, meetings need no doc parsing, so a plain
 * `internalAction` suffices — no `"use node"`. Scheduled from `create`
 * (and, in future, from any notes/transcript update).
 */
export const ingestMeeting = internalAction({
  args: { meetingId: v.id("meetings") },
  handler: async (ctx, { meetingId }) => {
    const meeting = await ctx.runQuery(internal.meetings.getForIngest, { meetingId });
    if (meeting === null) return; // deleted before ingest ran
    try {
      const text = [meeting.title, meeting.notes].filter(Boolean).join("\n\n");
      await ragAdd(ctx, {
        userId: meeting.userId,
        source: "meeting",
        sourceId: meetingId,
        title: meeting.title,
        text,
      });
    } catch (e) {
      // Meetings have no status field to mark failed (unlike documents) —
      // log only.
      console.error("ingestMeeting failed", meetingId, e);
    }
  },
});

/**
 * Internal-only maintenance action: re-ingest every existing meeting (e.g.
 * after this ingestion path first ships, or after a chunking/embedding
 * change). Not exposed publicly — run manually via `npx convex run
 * meetings:backfill`. `rag.add` is keyed by sourceId, so re-running is
 * idempotent (replaces the existing entry).
 */
export const backfill = internalAction({
  args: {},
  handler: async (ctx) => {
    const rows = await ctx.runQuery(internal.meetings.allMeetings, {});
    for (const row of rows) {
      await ctx.scheduler.runAfter(0, internal.meetings.ingestMeeting, { meetingId: row._id });
    }
  },
});
