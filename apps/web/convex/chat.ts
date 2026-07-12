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
  args: { threadId: v.string(), text: v.string() },
  handler: async (ctx, { threadId, text }) => {
    const userId = await requireUserId(ctx);
    await authorizeThread(ctx, threadId, userId);
    const trimmed = text.trim();
    if (trimmed.length > 0) {
      await ctx.runMutation(internal.chat.setThreadTitleIfEmpty, {
        threadId,
        title: trimmed.slice(0, 50),
      });
    }
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
  },
});
