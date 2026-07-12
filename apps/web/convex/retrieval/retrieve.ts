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
  const kept = cfg.rerankEnabled
    ? await rerank(boosted, args.query, cfg)
    : boosted.slice(0, cfg.keepN);

  return packContext(kept, cfg);
}
