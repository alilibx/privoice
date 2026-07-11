import { describe, expect, test } from "vitest";
import { chunkText } from "./chunk";

describe("chunkText", () => {
  test("blank input yields no chunks", () => {
    expect(chunkText("")).toEqual([]);
    expect(chunkText("   \n  ")).toEqual([]);
  });

  test("short text is a single chunk", () => {
    expect(chunkText("hello world")).toEqual(["hello world"]);
  });

  test("respects maxChars and overlaps", () => {
    const text = "a".repeat(7000);
    const chunks = chunkText(text, { maxChars: 3000, overlapChars: 300 });
    expect(chunks.length).toBeGreaterThanOrEqual(3);
    for (const c of chunks) expect(c.length).toBeLessThanOrEqual(3000);
    // consecutive chunks share the overlap tail/head
    expect(chunks[0].slice(-300)).toEqual(chunks[1].slice(0, 300));
  });

  test("no empty chunks for a huge input", () => {
    const chunks = chunkText("x ".repeat(60000), { maxChars: 3000, overlapChars: 300 });
    expect(chunks.every((c) => c.trim().length > 0)).toBe(true);
  });
});
