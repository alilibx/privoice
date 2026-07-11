// Calls OpenRouter's OpenAI-compatible embeddings endpoint. Server-only:
// reads OPENROUTER_API_KEY from the Convex env; never expose to the client.
const ENDPOINT = "https://openrouter.ai/api/v1/embeddings";
const MODEL = "openai/text-embedding-3-large";
const BATCH = 96;

export async function embedChunks(texts: string[]): Promise<number[][]> {
  const key = process.env.OPENROUTER_API_KEY;
  if (!key) throw new Error("OPENROUTER_API_KEY is not set");
  const out: number[][] = [];
  for (let i = 0; i < texts.length; i += BATCH) {
    const batch = texts.slice(i, i + BATCH);
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ model: MODEL, input: batch }),
    });
    if (!res.ok) {
      // Do not include the key or raw response that might echo headers.
      throw new Error(`Embeddings request failed (${res.status})`);
    }
    const json = (await res.json()) as { data: { embedding: number[]; index: number }[] };
    const sorted = json.data.sort((a, b) => a.index - b.index);
    for (const d of sorted) out.push(d.embedding);
  }
  return out;
}
