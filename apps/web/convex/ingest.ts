"use node";
import { v } from "convex/values";
import { internalAction } from "./_generated/server";
import { internal } from "./_generated/api";
import { chunkText } from "./lib/chunk";
import { embedChunks } from "./lib/embed";
import mammoth from "mammoth";
import * as XLSX from "xlsx";
// pdf-parse ^2.x is a full rewrite of the old (`pdf(buf) => {text}`) v1 API:
// it now exports a `PDFParse` class with an async `getText()` method. The
// installed version (see apps/web/package.json) does not have a default
// function export, so we use its real class-based API instead of the
// brief's literal `import pdf from "pdf-parse"` snippet.
import { PDFParse } from "pdf-parse";

async function extractText(kind: string, buf: Buffer): Promise<string> {
  switch (kind) {
    case "pdf": {
      const parser = new PDFParse({ data: buf });
      try {
        return (await parser.getText()).text;
      } finally {
        await parser.destroy();
      }
    }
    case "docx":
      return (await mammoth.extractRawText({ buffer: buf })).value;
    case "xlsx": {
      const wb = XLSX.read(buf, { type: "buffer" });
      return wb.SheetNames.map(
        (name) => `# ${name}\n${XLSX.utils.sheet_to_csv(wb.Sheets[name])}`,
      ).join("\n\n");
    }
    case "txt":
    case "md":
      return buf.toString("utf-8");
    default:
      throw new Error(`Unsupported kind: ${kind}`);
  }
}

export const ingestDocument = internalAction({
  args: { documentId: v.id("documents") },
  handler: async (ctx, { documentId }) => {
    const doc = await ctx.runQuery(internal.ingestStore.getDoc, { documentId });
    if (doc === null) return; // deleted before ingest ran
    try {
      const blob = await ctx.storage.get(doc.storageId);
      if (blob === null) throw new Error("File missing from storage");
      const buf = Buffer.from(await blob.arrayBuffer());
      const text = await extractText(doc.kind, buf);
      const chunks = chunkText(text);
      if (chunks.length === 0) throw new Error("No extractable text");
      const embeddings = await embedChunks(chunks);
      await ctx.runMutation(internal.ingestStore.insertChunks, {
        documentId,
        userId: doc.userId,
        chunks: chunks.map((text, i) => ({ text, embedding: embeddings[i] })),
      });
      await ctx.runMutation(internal.ingestStore.setReady, {
        documentId,
        chunkCount: chunks.length,
      });
    } catch (e) {
      await ctx.runMutation(internal.ingestStore.setFailed, {
        documentId,
        error: e instanceof Error ? e.message : "Ingestion failed",
      });
    }
  },
});
