import type { Candidate, RetrievalConfig, RetrievalResult, SourceRef } from "./types";

// Stable partition: pinned sources first (relative order preserved), then the
// rest (relative order preserved). All candidates retained, none dropped or
// duplicated.
export function pinAndBoost(fused: Candidate[], pinnedSourceIds: string[]): Candidate[] {
  const pinned = new Set(pinnedSourceIds);
  const front: Candidate[] = [];
  const rest: Candidate[] = [];
  for (const cand of fused) {
    (pinned.has(cand.sourceId) ? front : rest).push(cand);
  }
  return [...front, ...rest];
}

const CHARS_PER_TOKEN = 4;

function locatorFor(cand: Candidate): string {
  return cand.source === "meeting" ? "meeting" : "document";
}

// Number kept candidates [1..n] best-first, build a labeled pack string
// truncated to ~cfg.tokenBudget (chars ≈ tokens*4 heuristic), and the
// matching SourceRef[] for citations.
export function packContext(kept: Candidate[], cfg: RetrievalConfig): RetrievalResult {
  const charBudget = cfg.tokenBudget * CHARS_PER_TOKEN;
  const header = "# Context";
  let pack = header;
  const sources: SourceRef[] = [];

  kept.forEach((cand, i) => {
    const n = i + 1;
    const locator = locatorFor(cand);
    const chunk = `\n\n[${n}] ${cand.title} — ${locator}\n${cand.text}`;
    if (n > 1 && pack.length + chunk.length > charBudget) return;
    pack += chunk;
    sources.push({
      n,
      source: cand.source,
      sourceId: cand.sourceId,
      title: cand.title,
      locator,
    });
  });

  return { pack, sources };
}
