/** Lowercase hex SHA-256 of the given bytes (Web Crypto, browser-native). */
export async function sha256Hex(bytes: ArrayBuffer): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** SHA-256 (hex) of a File's contents — used to detect exact duplicates. */
export async function hashFile(file: File): Promise<string> {
  return sha256Hex(await file.arrayBuffer());
}
