// jsdom's Blob/File polyfill lacks arrayBuffer(); node's real File has it.
// @vitest-environment node
import { expect, test } from "vitest";
import { sha256Hex, hashFile } from "@/features/documents/content-hash";

test("sha256Hex matches known vectors", async () => {
  const empty = await sha256Hex(new Uint8Array().buffer);
  expect(empty).toBe(
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  );
  const abc = await sha256Hex(new TextEncoder().encode("abc").buffer);
  expect(abc).toBe(
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  );
});

test("hashFile hashes the file's bytes", async () => {
  const file = new File([new TextEncoder().encode("abc")], "a.txt", {
    type: "text/plain",
  });
  expect(await hashFile(file)).toBe(
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  );
});
