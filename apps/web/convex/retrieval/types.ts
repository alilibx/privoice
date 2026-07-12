export type Candidate = {
  key: string; // fusion key (see fuse.ts)
  entryId: string;
  source: string; // "document" | "meeting"
  sourceId: string;
  title: string;
  text: string;
  score: number; // arm-native score (cosine or bm25 rank proxy)
};

export type SourceRef = {
  n: number;
  source: string;
  sourceId: string;
  title: string;
  locator: string;
};

export type RetrievalConfig = {
  candidateK: number;
  fuseWeights: [number, number];
  rrfK: number;
  chunkContext: { before: number; after: number };
  vectorScoreThreshold: number;
  rerankEnabled: boolean;
  rerankModel: string;
  rerankPool: number;
  keepN: number;
  tokenBudget: number;
};

export type RetrievalResult = { pack: string; sources: SourceRef[] };
