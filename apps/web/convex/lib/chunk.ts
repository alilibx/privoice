/** Split text into overlapping chunks (char-based; ~3000 chars ≈ 800 tokens). */
export function chunkText(
  text: string,
  opts: { maxChars?: number; overlapChars?: number } = {},
): string[] {
  const maxChars = opts.maxChars ?? 3000;
  const overlapChars = Math.min(opts.overlapChars ?? 300, Math.floor(maxChars / 2));
  const clean = text.replace(/\r\n/g, "\n").trim();
  if (clean.length === 0) return [];
  if (clean.length <= maxChars) return [clean];

  const chunks: string[] = [];
  let start = 0;
  while (start < clean.length) {
    let end = Math.min(start + maxChars, clean.length);
    if (end < clean.length) {
      // Prefer to break on a nearby whitespace/newline boundary.
      const slice = clean.slice(start, end);
      const lastBreak = Math.max(slice.lastIndexOf("\n"), slice.lastIndexOf(" "));
      if (lastBreak > maxChars * 0.5) end = start + lastBreak + 1;
    }
    const piece = clean.slice(start, end).trim();
    if (piece.length > 0) chunks.push(clean.slice(start, end));
    if (end >= clean.length) break;
    start = end - overlapChars;
  }
  return chunks;
}
