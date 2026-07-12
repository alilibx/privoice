import type { RetrievalConfig } from "./types";

export const RETRIEVAL_CONFIG: RetrievalConfig = {
  candidateK: 20,
  fuseWeights: [1, 1],
  rrfK: 10,
  chunkContext: { before: 1, after: 1 },
  vectorScoreThreshold: 0.2,
  rerankEnabled: true,
  rerankModel: "openai/gpt-4o-mini",
  rerankPool: 30,
  keepN: 8,
  tokenBudget: 6000,
};
