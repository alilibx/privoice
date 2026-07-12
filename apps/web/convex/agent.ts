import { Agent, stepCountIs } from "@convex-dev/agent";
import { components } from "./_generated/api";
import { openrouter } from "./openrouter";
import { searchKnowledge, pinpoint } from "./tools";

// `languageModel` (not `chat`) is the Agent constructor's field name — see
// node_modules/@convex-dev/agent/dist/client/index.d.ts. `openrouter.chat(id)`
// (from @ai-sdk/openai's OpenAIProvider) returns the LanguageModelV3, pointed
// at OpenRouter via openrouter.ts's baseURL. "openai/gpt-4o-mini" is an
// OpenRouter-style model id (provider/model), matching rag.ts's
// `openrouter.embedding("openai/text-embedding-3-large")` convention.
export const chatAgent = new Agent(components.agent, {
  name: "Privoice Assistant",
  languageModel: openrouter.chat("openai/gpt-4o-mini"),
  instructions:
    "You are Privoice's assistant. Answer clearly and concisely. When the user asks about their documents or meetings, use the searchKnowledge / pinpoint tools and ground your answer in the results, noting the source. If a tool returns nothing relevant, say so instead of inventing facts. " +
    "Use searchKnowledge for questions about the user's documents or meetings; use pinpoint to find exact values (dates, amounts, clause numbers) within a known source. Ground every claim in the returned context and cite sources with [n] matching the numbered sources provided. Never cite a source that wasn't provided; if the context is insufficient, say so.",
  tools: { searchKnowledge, pinpoint },
  // Continue generating after a tool returns (tool call -> tool result ->
  // final answer) within a single turn — without this the agent stops after
  // the tool call and produces no text, forcing the user to re-ask.
  stopWhen: stepCountIs(5),
});
