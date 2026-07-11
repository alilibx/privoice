import { createOpenAI } from "@ai-sdk/openai";

// One OpenAI-compatible provider for both chat (agent, Task 2) and embeddings
// (rag, this task), pointed at OpenRouter. Server-only: OPENROUTER_API_KEY is
// read from `process.env` here and never sent to or logged for the client.
export const openrouter = createOpenAI({
  apiKey: process.env.OPENROUTER_API_KEY,
  baseURL: "https://openrouter.ai/api/v1",
});
