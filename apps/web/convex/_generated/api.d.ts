/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as agent from "../agent.js";
import type * as auth from "../auth.js";
import type * as chat from "../chat.js";
import type * as documents from "../documents.js";
import type * as http from "../http.js";
import type * as ingest from "../ingest.js";
import type * as ingestStore from "../ingestStore.js";
import type * as lib_chunk from "../lib/chunk.js";
import type * as meetings from "../meetings.js";
import type * as openrouter from "../openrouter.js";
import type * as rag from "../rag.js";
import type * as settings from "../settings.js";
import type * as tools from "../tools.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  agent: typeof agent;
  auth: typeof auth;
  chat: typeof chat;
  documents: typeof documents;
  http: typeof http;
  ingest: typeof ingest;
  ingestStore: typeof ingestStore;
  "lib/chunk": typeof lib_chunk;
  meetings: typeof meetings;
  openrouter: typeof openrouter;
  rag: typeof rag;
  settings: typeof settings;
  tools: typeof tools;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {
  agent: import("@convex-dev/agent/_generated/component.js").ComponentApi<"agent">;
  rag: import("@convex-dev/rag/_generated/component.js").ComponentApi<"rag">;
};
