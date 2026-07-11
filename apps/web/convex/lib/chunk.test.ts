import { describe, expect, test } from "vitest";
import { chunkText } from "./chunk";

/** Length of the longest suffix of `a` that is also a prefix of `b`. */
function overlapLength(a: string, b: string): number {
  const max = Math.min(a.length, b.length);
  for (let n = max; n > 0; n--) {
    if (a.slice(-n) === b.slice(0, n)) return n;
  }
  return 0;
}

describe("chunkText", () => {
  test("blank/whitespace input yields no chunks", () => {
    expect(chunkText("")).toEqual([]);
    expect(chunkText("   \n  \n\n  ")).toEqual([]);
  });

  test("short text is a single chunk", () => {
    expect(chunkText("hello world")).toEqual(["hello world"]);
  });

  test("defaults are maxChars=2000, overlapChars=200 (~512 tok, 10%)", () => {
    const text = "word ".repeat(1000); // 5000 chars, plenty of spaces to split on
    const chunks = chunkText(text);
    expect(chunks.length).toBeGreaterThanOrEqual(2);
    for (const c of chunks) expect(c.length).toBeLessThanOrEqual(2000);
  });

  test("every chunk is non-empty and within maxChars", () => {
    const text = Array.from({ length: 40 }, (_, i) => `Paragraph number ${i} has some words in it.`).join(
      "\n\n",
    );
    const chunks = chunkText(text, { maxChars: 300, overlapChars: 30 });
    expect(chunks.length).toBeGreaterThan(1);
    for (const c of chunks) {
      expect(c.trim().length).toBeGreaterThan(0);
      expect(c.length).toBeLessThanOrEqual(300);
    }
  });

  test("short paragraphs are not cut mid-paragraph", () => {
    const paragraphs = [
      "This is the first short paragraph about apples.",
      "This is the second short paragraph about oranges.",
      "This is the third short paragraph about bananas.",
      "This is the fourth short paragraph about grapes.",
      "This is the fifth short paragraph about pears.",
    ];
    const text = paragraphs.join("\n\n");
    // maxChars comfortably bigger than any single paragraph, but smaller than
    // the whole document, so multiple chunks are produced.
    const chunks = chunkText(text, { maxChars: 150, overlapChars: 0 });
    expect(chunks.length).toBeGreaterThan(1);
    for (const p of paragraphs) {
      expect(chunks.some((c) => c.includes(p))).toBe(true);
    }
  });

  test("consecutive chunks overlap when overlapChars > 0", () => {
    const sentences = Array.from(
      { length: 20 },
      (_, i) => `This is sentence number ${i} with a handful of words in it.`,
    );
    const text = sentences.join(" ");
    const chunks = chunkText(text, { maxChars: 200, overlapChars: 40 });
    expect(chunks.length).toBeGreaterThanOrEqual(3);
    for (let i = 1; i < chunks.length; i++) {
      const n = overlapLength(chunks[i - 1], chunks[i]);
      expect(n).toBeGreaterThan(10); // meaningfully overlapping, not just a shared letter
    }
  });

  test("no overlap when overlapChars <= 0", () => {
    const text = "word ".repeat(500);
    const chunks = chunkText(text, { maxChars: 200, overlapChars: 0 });
    expect(chunks.length).toBeGreaterThan(1);
    const joined = chunks.join("");
    // Reconstructing without overlap should stay close to the source length
    // (only separator whitespace may differ), i.e. no duplicated tails.
    expect(joined.length).toBeLessThanOrEqual(text.trim().length + chunks.length);
  });

  test("single chunk never gets overlap", () => {
    expect(chunkText("short text here", { maxChars: 2000, overlapChars: 200 })).toEqual([
      "short text here",
    ]);
  });

  test("Arabic multi-sentence text splits on Arabic punctuation, not mid-word", () => {
    const arabic =
      "مرحبا بكم في هذا الاجتماع اليوم؟ سنتحدث عن الخطة القادمة، وسنراجع الميزانية أيضا! " +
      "هل لديكم أسئلة حول الجدول الزمني، أم تريدون الانتقال مباشرة إلى المرحلة التالية. " +
      "شكرا لحضوركم جميعا اليوم؟ نتمنى لكم يوما سعيدا، ونراكم في الاجتماع القادم!";
    const chunks = chunkText(arabic, { maxChars: 70, overlapChars: 0 });
    expect(chunks.length).toBeGreaterThan(1);
    const boundaryChars = new Set([" ", "\n", ".", "؟", "!", "،"]);
    for (let i = 0; i < chunks.length - 1; i++) {
      const last = chunks[i].slice(-1);
      expect(boundaryChars.has(last)).toBe(true);
    }
    for (const c of chunks) expect(c.length).toBeLessThanOrEqual(70);
  });

  test("a very long word/URL with no separators hard-cuts into <= maxChars pieces", () => {
    const longUrl = "https://example.com/" + "a".repeat(5000);
    const chunks = chunkText(longUrl, { maxChars: 2000, overlapChars: 0 });
    expect(chunks.length).toBeGreaterThanOrEqual(3);
    for (const c of chunks) {
      expect(c.trim().length).toBeGreaterThan(0);
      expect(c.length).toBeLessThanOrEqual(2000);
    }
    expect(chunks.join("")).toEqual(longUrl);
  });
});
