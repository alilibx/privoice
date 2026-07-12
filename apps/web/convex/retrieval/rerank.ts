import { generateText } from "ai";
import { openrouter } from "../openrouter";
import type { Candidate, RetrievalConfig } from "./types";

export type GenerateFn = (args: { model: string; prompt: string }) => Promise<string>;

// Default generate: routes through OpenRouter via the `ai` SDK. Only ever
// exercised in production (Task 6 wires this in) — tests inject `deps.generate`
// so the rerank logic itself is unit-testable offline.
const defaultGenerate: GenerateFn = ({ model, prompt }) =>
  generateText({ model: openrouter.chat(model), prompt }).then((r) => r.text);

function buildPrompt(pool: Candidate[], query: string, keepN: number): string {
  const listing = pool
    .map((c, i) => `[${i}] ${c.title}\n${c.text}`)
    .join("\n\n");
  return (
    `Query: ${query}\n\n` +
    `Candidates:\n${listing}\n\n` +
    `Return JSON {"keep":[indices]} of the up-to-${keepN} most relevant candidate ` +
    `indices above (0-based) to the query, best first. Respond with JSON only.`
  );
}

// Parses the model's raw text defensively: must be JSON with a `keep` array
// of in-range integers. Dedupes while preserving order and clamps to keepN.
// Any structural problem throws, which the caller turns into a fail-soft.
function parseKeep(raw: string, poolSize: number, keepN: number): number[] {
  const parsed: unknown = JSON.parse(raw);
  if (typeof parsed !== "object" || parsed === null || !("keep" in parsed)) {
    throw new Error("missing keep field");
  }
  const keep = (parsed as { keep: unknown }).keep;
  if (!Array.isArray(keep)) throw new Error("keep is not an array");

  const seen = new Set<number>();
  const indices: number[] = [];
  for (const v of keep) {
    if (typeof v !== "number" || !Number.isInteger(v) || v < 0 || v >= poolSize) {
      throw new Error("keep contains an out-of-range or non-integer value");
    }
    if (seen.has(v)) continue;
    seen.add(v);
    indices.push(v);
  }
  return indices.slice(0, keepN);
}

// Fail-soft LLM-judge rerank: scores the top `cfg.rerankPool` fused candidates
// with a single model call and returns the model's chosen best `cfg.keepN`,
// in the order it picked them. ANY error along the way (throw or unparseable
// output) falls back to `fused.slice(0, cfg.keepN)` — this stage never throws.
export async function rerankCandidates(
  fused: Candidate[],
  query: string,
  cfg: RetrievalConfig,
  deps?: { generate?: GenerateFn },
): Promise<Candidate[]> {
  const fallback = () => fused.slice(0, cfg.keepN);
  try {
    const pool = fused.slice(0, cfg.rerankPool);
    const generate = deps?.generate ?? defaultGenerate;
    const raw = await generate({ model: cfg.rerankModel, prompt: buildPrompt(pool, query, cfg.keepN) });
    const indices = parseKeep(raw, pool.length, cfg.keepN);
    if (indices.length === 0) return fallback();
    return indices.map((i) => pool[i]);
  } catch {
    return fallback();
  }
}
