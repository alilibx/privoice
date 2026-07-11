/**
 * Recursive character splitter (LangChain-style), Arabic-aware.
 *
 * Splits text along a hierarchy of separators — paragraph, line, sentence
 * (including Arabic `؟` question mark and `،` comma), word, then a hard
 * character cut — so that semantic units (paragraphs, sentences, words) stay
 * intact whenever possible. Fine pieces are then greedily packed into chunks
 * targeting `maxChars - overlapChars`, and consecutive chunks get an overlap
 * prefix (trimmed to a word boundary) so retrieval doesn't lose context at a
 * chunk boundary.
 */

const SEPARATORS = ["\n\n", "\n", ". ", "؟", "!", "،", " ", ""];

export function chunkText(
  text: string,
  opts: { maxChars?: number; overlapChars?: number } = {},
): string[] {
  const maxChars = opts.maxChars ?? 2000;
  const overlapChars = Math.max(0, Math.min(opts.overlapChars ?? 200, Math.floor(maxChars / 2)));

  const clean = text.replace(/\r\n/g, "\n").trim();
  if (clean.length === 0) return [];
  if (clean.length <= maxChars) return [clean];

  const pieces = recursiveSplit(clean, SEPARATORS, maxChars).filter((p) => p.trim().length > 0);

  const targetSize = Math.max(1, maxChars - overlapChars);
  const merged = greedyMerge(pieces, targetSize);

  return addOverlap(merged, overlapChars, maxChars);
}

/** Recursively split `text` by the separator hierarchy until every piece is <= maxChars. */
function recursiveSplit(text: string, separators: string[], maxChars: number): string[] {
  if (text.length <= maxChars) return [text];
  if (separators.length === 0) return hardCut(text, maxChars);

  const [sep, ...rest] = separators;
  if (sep === "") return hardCut(text, maxChars);

  const rawParts = text.split(sep);
  const pieces: string[] = [];
  for (let i = 0; i < rawParts.length; i++) {
    const isLast = i === rawParts.length - 1;
    // Re-attach the separator to the end of each piece (except the last) so
    // sentence/paragraph punctuation stays with the text it terminates.
    const piece = isLast ? rawParts[i] : rawParts[i] + sep;
    if (piece.trim().length === 0) continue;
    if (piece.length > maxChars) {
      pieces.push(...recursiveSplit(piece, rest, maxChars));
    } else {
      pieces.push(piece);
    }
  }
  return pieces;
}

/** Hard character cut — last-resort fallback for text with no separators (e.g. a long URL). */
function hardCut(text: string, maxChars: number): string[] {
  const out: string[] = [];
  for (let i = 0; i < text.length; i += maxChars) {
    out.push(text.slice(i, i + maxChars));
  }
  return out;
}

/** Greedily pack consecutive fine-grained pieces into chunks targeting `targetSize`. */
function greedyMerge(pieces: string[], targetSize: number): string[] {
  const chunks: string[] = [];
  let current = "";
  for (const piece of pieces) {
    if (current.length === 0) {
      current = piece;
    } else if (current.length + piece.length <= targetSize) {
      current += piece;
    } else {
      chunks.push(current);
      current = piece;
    }
  }
  if (current.length > 0) chunks.push(current);
  return chunks;
}

/**
 * Prepend roughly the last `overlapChars` characters of the previous
 * (pre-overlap) chunk to each subsequent chunk, trimmed to a word boundary
 * and capped so the result never exceeds maxChars.
 */
function addOverlap(chunks: string[], overlapChars: number, maxChars: number): string[] {
  if (overlapChars <= 0 || chunks.length < 2) return chunks;

  const result: string[] = [chunks[0]];
  for (let i = 1; i < chunks.length; i++) {
    const prevOriginal = chunks[i - 1];
    const current = chunks[i];
    const budget = Math.max(0, Math.min(overlapChars, maxChars - current.length));
    let tail = prevOriginal.slice(-budget);
    if (budget > 0 && tail.length === budget && prevOriginal.length > budget) {
      // Avoid starting the overlap mid-word: drop the partial word before the
      // first word boundary in the tail, if there is one.
      const boundaryIdx = tail.search(/[\s.؟!،]/);
      if (boundaryIdx > 0) tail = tail.slice(boundaryIdx + 1);
      else if (boundaryIdx === 0) tail = tail.slice(1);
    }
    result.push(tail + current);
  }
  return result;
}
