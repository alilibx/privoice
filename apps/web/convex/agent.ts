import { Agent } from "@convex-dev/agent";
import { components } from "./_generated/api";
import { openrouter } from "./openrouter";
import { searchDocuments, searchMeetings } from "./tools";

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
    "You are Privoice's assistant. Answer clearly and concisely. When the user asks about their documents or meetings, use the searchDocuments / searchMeetings tools and ground your answer in the results, noting the source. If a tool returns nothing relevant, say so instead of inventing facts.",
  tools: { searchDocuments, searchMeetings },
});
