import type { ActionCtx } from "../_generated/server";
import { bm25Candidates, vectorCandidates } from "./candidates";
import { RETRIEVAL_CONFIG } from "./config";
import { fuseCandidates } from "./fuse";
import { pinAndBoost, packContext } from "./pack";
import { rerankCandidates } from "./rerank";
import type { Candidate, RetrievalConfig, RetrievalResult } from "./types";

type CandidateFn = (
  ctx: ActionCtx,
  args: { userId: string; query: string; source?: string; cfg: RetrievalConfig },
) => Promise<Candidate[]>;

type RerankFn = (
  cands: Candidate[],
  query: string,
  cfg: RetrievalConfig,
) => Promise<Candidate[]>;

export type RetrieveDeps = {
  vector?: CandidateFn;
  bm25?: CandidateFn;
  rerank?: RerankFn;
};

export type RetrieveArgs = {
  userId: string;
  query: string;
  source?: string;
  pinnedSourceIds: string[];
  cfg?: RetrievalConfig;
  deps?: RetrieveDeps;
};

const EMPTY_RESULT: RetrievalResult = {
  pack: "No matching documents or meetings.",
  sources: [],
};

// Dedupe by fusion `key`, keeping the FIRST occurrence's position — used to
// reinject pinned candidates ahead of the reranked list without duplicating
// a candidate that both lists happen to contain.
function dedupeByKey(cands: Candidate[]): Candidate[] {
  const seen = new Set<string>();
  const out: Candidate[] = [];
  for (const cand of cands) {
    if (seen.has(cand.key)) continue;
    seen.add(cand.key);
    out.push(cand);
  }
  return out;
}

// Fail-soft arm runner: on throw, log and return [] so one broken retrieval
// arm never takes down the other.
async function runArm(name: string, fn: () => Promise<Candidate[]>): Promise<Candidate[]> {
  try {
    return await fn();
  } catch (err) {
    console.error(`retrieve: ${name} arm failed`, err);
    return [];
  }
}

// Orchestrates the full retrieval pipeline: vector + BM25 candidate search
// (each fail-soft), RRF fusion, pin/boost, optional LLM rerank, and context
// packing. `deps` lets tests stub out the three I/O-bound stages.
export async function retrieve(ctx: ActionCtx, args: RetrieveArgs): Promise<RetrievalResult> {
  const cfg = args.cfg ?? RETRIEVAL_CONFIG;
  const vector = args.deps?.vector ?? vectorCandidates;
  const bm25 = args.deps?.bm25 ?? bm25Candidates;
  const rerank = args.deps?.rerank ?? rerankCandidates;

  const candArgs = { userId: args.userId, query: args.query, source: args.source, cfg };

  const [vectorResults, bm25Results] = await Promise.all([
    runArm("vector", () => vector(ctx, candArgs)),
    runArm("bm25", () => bm25(ctx, candArgs)),
  ]);

  if (vectorResults.length === 0 && bm25Results.length === 0) {
    return EMPTY_RESULT;
  }

  const fused = fuseCandidates(bm25Results, vectorResults, cfg);
  const boosted = pinAndBoost(fused, args.pinnedSourceIds);

  let kept: Candidate[];
  if (cfg.rerankEnabled) {
    // Pinned sources must always survive rerank (inclusive guarantee), but
    // an LLM reranker only returns its own chosen `keepN` subset and can
    // drop a pinned candidate entirely. Reinject the pinned candidates
    // (from `boosted`, so pin/boost ordering is preserved) ahead of
    // whatever the reranker kept, dedupe by fusion key, then cap at
    // keepN — pinned first, reranked remainder after. When there are no
    // pins this is a no-op and behavior is unchanged.
    const pinnedSet = new Set(args.pinnedSourceIds);
    const pinned = boosted.filter((c) => pinnedSet.has(c.sourceId));
    const ranked = await rerank(boosted, args.query, cfg);
    kept = dedupeByKey([...pinned, ...ranked]).slice(0, cfg.keepN);
  } else {
    kept = boosted.slice(0, cfg.keepN);
  }

  return packContext(kept, cfg);
}
