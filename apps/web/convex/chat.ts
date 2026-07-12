import { v, ConvexError } from "convex/values";
import { paginationOptsValidator } from "convex/server";
import {
  query,
  mutation,
  action,
  internalQuery,
  internalMutation,
  type QueryCtx,
  type MutationCtx,
  type ActionCtx,
} from "./_generated/server";
import { components, internal } from "./_generated/api";
import { getAuthUserId } from "@convex-dev/auth/server";
import { listUIMessages, syncStreams, vStreamArgs } from "@convex-dev/agent";
import { chatAgent } from "./agent";
import { openrouter } from "./openrouter";
import { DEFAULT_MODEL, isAllowedModel } from "./models.shared";

async function requireUserId(ctx: QueryCtx | MutationCtx | ActionCtx) {
  const userId = await getAuthUserId(ctx as any);
  if (userId === null) throw new ConvexError("Not authenticated");
  return userId;
}

/**
 * Ownership check backing every thread-scoped chat function. `chatThreads`
 * (see schema.ts) is OUR OWN side table mapping the agent component's
 * threadId to the userId that created it — set once in `createThread` below
 * and never mutated. We check it here (rather than trusting the agent
 * component's own thread metadata) so this gate is real Convex-table logic
 * that convex-test can exercise directly, and doesn't depend on the
 * (headless-untestable) agent/rag components being wired up.
 *
 * Query/mutation ctx has `ctx.db` directly; action ctx only has
 * `ctx.runQuery`, so we route through the internal `getThreadOwner` query
 * there. Throws a generic "Not found" on any mismatch — never reveals
 * whether the thread exists for someone else.
 */
async function authorizeThread(
  ctx: QueryCtx | MutationCtx | ActionCtx,
  threadId: string,
  userId: string,
) {
  const row =
    "db" in ctx
      ? await ctx.db
          .query("chatThreads")
          .withIndex("by_thread", (q) => q.eq("threadId", threadId))
          .unique()
      : await ctx.runQuery(internal.chat.getThreadOwner, { threadId });
  if (row === null || row.userId !== userId) {
    throw new ConvexError("Not found"); // don't reveal others' threads
  }
  return row;
}

// Internal-only: lets `sendMessage` (an action, no `ctx.db`) reuse the same
// ownership row that `listThreads`/`listMessages` read directly via `ctx.db`.
export const getThreadOwner = internalQuery({
  args: { threadId: v.string() },
  handler: async (ctx, { threadId }) => {
    return await ctx.db
      .query("chatThreads")
      .withIndex("by_thread", (q) => q.eq("threadId", threadId))
      .unique();
  },
});

// Internal-only: lets `sendMessage` (an action, no `ctx.db`) read the
// caller's saved model preference. Returns the RAW stored value (or
// DEFAULT_MODEL if unset) — `sendMessage` itself re-validates the result
// against `isAllowedModel` and fails closed to DEFAULT_MODEL, so this stays
// safe even if `userSettings.modelId` were ever populated by anything other
// than settings.ts's allowlist-checked `setModel`.
export const getUserModel = internalQuery({
  args: { userId: v.id("users") },
  handler: async (ctx, { userId }) => {
    const row = await ctx.db
      .query("userSettings")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .unique();
    return row?.modelId ?? DEFAULT_MODEL;
  },
});

export const listThreads = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    return await ctx.db
      .query("chatThreads")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .order("desc")
      .collect();
  },
});

export const createThread = mutation({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    // Mutation-ctx overload of Agent#createThread returns just { threadId }
    // (no `thread` object — that requires an action ctx for generation).
    // We still pass userId so the agent component's own thread metadata
    // carries it too (used for its cross-thread search-by-user feature),
    // but OUR authorization gate is the chatThreads row inserted below.
    const { threadId } = await chatAgent.createThread(ctx, { userId });
    await ctx.db.insert("chatThreads", {
      threadId,
      userId,
      createdAt: Date.now(),
    });
    return threadId;
  },
});

export const deleteThread = mutation({
  args: { threadId: v.string() },
  handler: async (ctx, { threadId }) => {
    const userId = await requireUserId(ctx);
    // Ownership gate — throws generic "Not found" for a non-owner, never
    // revealing another user's thread.
    await authorizeThread(ctx, threadId, userId);
    // Remove OUR ownership record first, so the thread disappears from the
    // user's list immediately (no orphan visible if the async agent delete
    // lags).
    const row = await ctx.db
      .query("chatThreads")
      .withIndex("by_thread", (q) => q.eq("threadId", threadId))
      .unique();
    if (row !== null) await ctx.db.delete(row._id);
    // Delete the agent component's messages + streams for this thread
    // (batched, safe from a mutation ctx).
    await chatAgent.deleteThreadAsync(ctx, { threadId });
    return null;
  },
});

// Internal-only: sets a thread's title from its first user message, but
// never overwrites one that's already set. Reached exclusively through
// `sendMessage`, which has already authorized the caller as the thread
// owner — there is no public path that lets a client set an arbitrary
// thread's title.
export const setThreadTitleIfEmpty = internalMutation({
  args: { threadId: v.string(), title: v.string() },
  handler: async (ctx, { threadId, title }) => {
    const row = await ctx.db
      .query("chatThreads")
      .withIndex("by_thread", (q) => q.eq("threadId", threadId))
      .unique();
    if (row === null || row.title) return; // missing row, or already titled
    await ctx.db.patch(row._id, { title });
  },
});

// Internal-only: reads back the ids the caller owns from the ones the
// client claimed to attach. Checks BOTH `documents` and `meetings` by `_id`
// AND `userId` match — a raw client-supplied id is otherwise meaningless
// (could belong to another user, or not exist/be the wrong table at all).
// `ctx.db.normalizeId` safely turns a string into a validated Id for a given
// table (returning null if it isn't one), so this never throws on garbage
// input — it just silently drops it, per the security requirement that a
// non-owned id is dropped rather than surfaced as an error.
export const validatePins = internalQuery({
  args: { userId: v.id("users"), sourceIds: v.array(v.string()) },
  handler: async (ctx, { userId, sourceIds }) => {
    const valid: string[] = [];
    for (const sourceId of sourceIds) {
      const docId = ctx.db.normalizeId("documents", sourceId);
      if (docId !== null) {
        const doc = await ctx.db.get(docId);
        if (doc !== null && doc.userId === userId) {
          valid.push(sourceId);
          continue;
        }
      }
      const meetingId = ctx.db.normalizeId("meetings", sourceId);
      if (meetingId !== null) {
        const meeting = await ctx.db.get(meetingId);
        if (meeting !== null && meeting.userId === userId) {
          valid.push(sourceId);
        }
      }
    }
    return valid;
  },
});

// Internal-only: the per-user "pinned for this turn" row read by
// searchKnowledge (see tools.ts) so pinAndBoost can prioritize whatever
// documents/meetings are attached to the message currently being generated.
export const getPins = internalQuery({
  args: { userId: v.id("users") },
  handler: async (ctx, { userId }) => {
    const row = await ctx.db
      .query("retrievalPins")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .unique();
    return row?.sourceIds ?? [];
  },
});

// Internal-only: upserts (never inserts a second row per user) the caller's
// pin set. `sendMessage` calls this with the VALIDATED ids right before
// generation starts, then again with `[]` right after generation finishes —
// pins are scoped to a single turn, not a durable setting.
export const setPins = internalMutation({
  args: { userId: v.id("users"), sourceIds: v.array(v.string()) },
  handler: async (ctx, { userId, sourceIds }) => {
    const row = await ctx.db
      .query("retrievalPins")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .unique();
    if (row !== null) {
      await ctx.db.patch(row._id, { sourceIds, updatedAt: Date.now() });
    } else {
      await ctx.db.insert("retrievalPins", { userId, sourceIds, updatedAt: Date.now() });
    }
  },
});

export const listMessages = query({
  args: {
    threadId: v.string(),
    paginationOpts: paginationOptsValidator,
    streamArgs: vStreamArgs,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await authorizeThread(ctx, args.threadId, userId);
    const paginated = await listUIMessages(ctx, components.agent, args);
    const streams = await syncStreams(ctx, components.agent, args);
    return { ...paginated, streams };
  },
});

export const sendMessage = action({
  args: {
    threadId: v.string(),
    text: v.string(),
    // Ids of documents/meetings attached to this message by the client.
    // SECURITY: this is untrusted client input — never stored or used
    // as-is. Validated below via `internal.chat.validatePins`, which drops
    // anything the caller doesn't own, before it's ever persisted or read by
    // a tool.
    pinnedSourceIds: v.optional(v.array(v.string())),
  },
  handler: async (ctx, { threadId, text, pinnedSourceIds }) => {
    const userId = await requireUserId(ctx);
    await authorizeThread(ctx, threadId, userId);
    const trimmed = text.trim();
    if (trimmed.length > 0) {
      await ctx.runMutation(internal.chat.setThreadTitleIfEmpty, {
        threadId,
        title: trimmed.slice(0, 50),
      });
    }
    // Validate the claimed attachment ids against ownership BEFORE they're
    // pinned for this turn — a non-owned id is silently dropped, never
    // trusted. Pins are set unconditionally (even to `[]`) so any stale pin
    // from a prior turn (e.g. left over from an action that crashed before
    // its own cleanup ran) can never leak into this generation.
    const validPinnedSourceIds = await ctx.runQuery(internal.chat.validatePins, {
      userId,
      sourceIds: pinnedSourceIds ?? [],
    });
    await ctx.runMutation(internal.chat.setPins, {
      userId,
      sourceIds: validPinnedSourceIds,
    });
    try {
      // Passing `userId` explicitly here (the server-resolved authenticated
      // caller, never client input) is what makes every tool call during this
      // generation see `ctx.userId === userId` — see start.js's
      // `opts.userId ?? thread.userId` fallback and tools.ts's
      // `requireCallerUserId`. This is the crux of the per-user tool isolation:
      // it holds regardless of what's stored on the thread itself.
      const { thread } = await chatAgent.continueThread(ctx, {
        threadId,
        userId,
      });
      // SECURITY: the generation model is resolved and validated server-side,
      // never taken from client input (sendMessage's own args have no model
      // field at all). `getUserModel` returns whatever's stored, but we
      // re-validate here and fail closed to DEFAULT_MODEL — defense in depth
      // against a stored value that somehow bypassed setModel's allowlist
      // check.
      const rawModelId = await ctx.runQuery(internal.chat.getUserModel, {
        userId,
      });
      const modelId = isAllowedModel(rawModelId) ? rawModelId : DEFAULT_MODEL;
      const result = await thread.streamText(
        { prompt: text, model: openrouter.chat(modelId) },
        { saveStreamDeltas: true },
      );
      // Drain the stream fully within the action so every delta is saved and
      // the action doesn't return before generation (and any tool calls)
      // finish.
      await result.consumeStream();
    } finally {
      // Pins are scoped to this single turn only — always clear them once
      // generation is done (or has thrown), so they never leak into the
      // next, unrelated message.
      await ctx.runMutation(internal.chat.setPins, { userId, sourceIds: [] });
    }
  },
});
