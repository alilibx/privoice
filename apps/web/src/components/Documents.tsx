import { useState } from "react";
import { useQuery, useMutation } from "convex/react";
import { api } from "../../convex/_generated/api";

export default function Documents() {
  const docs = useQuery(api.documents.list) ?? [];
  const generateUploadUrl = useMutation(api.documents.generateUploadUrl);
  const create = useMutation(api.documents.create);
  const remove = useMutation(api.documents.remove);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function upload(file: File) {
    setBusy(true); setError(null);
    try {
      const url = await generateUploadUrl();
      const res = await fetch(url, { method: "POST", headers: { "Content-Type": file.type }, body: file });
      const { storageId } = await res.json();
      await create({ storageId, filename: file.name, mimeType: file.type, sizeBytes: file.size });
    } catch (e) {
      setError(e instanceof Error ? e.message : "Upload failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="mx-auto max-w-2xl p-6">
      <h1 className="text-2xl font-bold text-primary">Documents</h1>
      <label className="mt-6 block cursor-pointer rounded-xl border border-dashed border-outline bg-surface p-6 text-center text-on-surface-variant">
        {busy ? "Uploading…" : "Click to upload a file (PDF, Word, Excel, txt, md)"}
        <input type="file" accept=".pdf,.docx,.xlsx,.txt,.md" className="hidden"
          onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); e.target.value = ""; }} />
      </label>
      {error && <p className="mt-2 text-sm text-red-600">{error}</p>}
      <ul className="mt-6 space-y-2">
        {docs.map((d: any) => (
          <li key={d._id} className="flex items-center justify-between rounded-xl border border-outline bg-surface p-4">
            <span className="truncate">{d.filename}</span>
            <span className="flex items-center gap-3 text-sm">
              <StatusChip status={d.status} chunkCount={d.chunkCount} error={d.error} />
              <button onClick={() => remove({ id: d._id })}
                className="text-on-surface-variant hover:text-red-600">Delete</button>
            </span>
          </li>
        ))}
        {docs.length === 0 && <li className="text-on-surface-variant">No documents yet.</li>}
      </ul>
    </section>
  );
}

function StatusChip({ status, chunkCount, error }: { status: string; chunkCount: number; error?: string }) {
  if (status === "ready") return <span className="text-primary">Ready · {chunkCount} chunks</span>;
  if (status === "failed") return <span className="text-red-600" title={error}>Failed</span>;
  return <span className="text-on-surface-variant">Parsing…</span>;
}
