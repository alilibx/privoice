import { useState } from "react";
import { useQuery, useMutation } from "convex/react";
import { toast } from "sonner";
import { api } from "../../../convex/_generated/api";
import type { Id } from "../../../convex/_generated/dataModel";
import DocumentCard, { type DocumentRow } from "@/features/documents/DocumentCard";
import UploadDropzone from "@/features/documents/UploadDropzone";

export default function DocumentsList() {
  const docs = (useQuery(api.documents.list) ?? []) as DocumentRow[];
  const generateUploadUrl = useMutation(api.documents.generateUploadUrl);
  const create = useMutation(api.documents.create);
  const remove = useMutation(api.documents.remove);
  const [busy, setBusy] = useState(false);

  async function upload(file: File) {
    setBusy(true);
    try {
      const url = await generateUploadUrl();
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": file.type },
        body: file,
      });
      const { storageId } = await res.json();
      await create({
        storageId,
        filename: file.name,
        mimeType: file.type,
        sizeBytes: file.size,
      });
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Upload failed");
    } finally {
      setBusy(false);
    }
  }

  async function handleDelete(id: string) {
    try {
      await remove({ id: id as Id<"documents"> });
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to delete document");
    }
  }

  return (
    <section className="mx-auto max-w-3xl p-6">
      <h1 className="text-2xl font-bold text-foreground">Documents</h1>

      <div className="mt-6">
        <UploadDropzone onFile={(f) => void upload(f)} busy={busy} />
      </div>

      {docs.length === 0 ? (
        <p className="mt-8 text-center text-muted-foreground">No documents yet</p>
      ) : (
        <div className="mt-6 grid grid-cols-1 gap-3 sm:grid-cols-2">
          {docs.map((d) => (
            <DocumentCard key={d._id} doc={d} onDelete={(id) => void handleDelete(id)} />
          ))}
        </div>
      )}
    </section>
  );
}
