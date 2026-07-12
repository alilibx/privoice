"use node";
import { v } from "convex/values";
import { internalAction } from "./_generated/server";
import { internal } from "./_generated/api";
import { ragAdd } from "./rag";
import mammoth from "mammoth";
import * as XLSX from "xlsx";
// PDF text extraction via `unpdf` — a serverless build of pdf.js with NO
// canvas/DOM dependency (pdf-parse@2 / raw pdf.js reference DOMMatrix at load
// time, which the Convex Node runtime can't provide → deploy fails). unpdf's
// text path works across Node/edge/serverless.
import { extractText as extractPdfText, getDocumentProxy } from "unpdf";

async function extractText(kind: string, buf: Buffer): Promise<string> {
  switch (kind) {
    case "pdf": {
      const pdf = await getDocumentProxy(new Uint8Array(buf));
      const { text } = await extractPdfText(pdf, { mergePages: true });
      return text;
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
      if (text.trim().length === 0) throw new Error("No extractable text");
      // rag.add chunks (via our splitter) + embeds (via OpenRouter) + stores,
      // keyed by documentId within this user's namespace — see rag.ts.
      const { chunkCount } = await ragAdd(ctx, {
        userId: doc.userId,
        source: "document",
        sourceId: documentId,
        title: doc.filename,
        text,
      });
      await ctx.runMutation(internal.ingestStore.setReady, {
        documentId,
        chunkCount,
      });
    } catch (e) {
      await ctx.runMutation(internal.ingestStore.setFailed, {
        documentId,
        error: e instanceof Error ? e.message : "Ingestion failed",
      });
    }
  },
});
