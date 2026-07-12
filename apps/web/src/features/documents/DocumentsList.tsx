import { useState } from "react";
import { useQuery, useMutation } from "convex/react";
import { toast } from "sonner";
import { api } from "../../../convex/_generated/api";
import type { Id } from "../../../convex/_generated/dataModel";
import PageHeader from "@/components/layout/PageHeader";
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
    <div className="flex h-full flex-col">
      <PageHeader title="Documents" />
      <div className="flex-1 overflow-y-auto">
        <div className="mx-auto max-w-3xl p-4 sm:p-6">
          <UploadDropzone onFile={(f) => void upload(f)} busy={busy} />
          {docs.length === 0 ? (
            <p className="mt-16 text-center text-muted-foreground">
              No documents yet
            </p>
          ) : (
            <div className="mt-6 grid grid-cols-1 gap-3 sm:grid-cols-2">
              {docs.map((d) => (
                <DocumentCard
                  key={d._id}
                  doc={d}
                  onDelete={(id) => void handleDelete(id)}
                />
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
