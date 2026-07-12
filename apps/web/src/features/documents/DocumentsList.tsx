import { useState } from "react";
import { useQuery, useMutation } from "convex/react";
import { toast } from "sonner";
import { api } from "../../../convex/_generated/api";
import type { Id } from "../../../convex/_generated/dataModel";
import PageHeader from "@/components/layout/PageHeader";
import DocumentCard, { type DocumentRow } from "@/features/documents/DocumentCard";
import UploadDropzone from "@/features/documents/UploadDropzone";
import DuplicateDialog from "@/features/documents/DuplicateDialog";
import { hashFile } from "@/features/documents/content-hash";

export default function DocumentsList() {
  const docs = (useQuery(api.documents.list) ?? []) as DocumentRow[];
  const generateUploadUrl = useMutation(api.documents.generateUploadUrl);
  const create = useMutation(api.documents.create);
  const remove = useMutation(api.documents.remove);
  const [busy, setBusy] = useState(false);
  // The file awaiting a duplicate decision, plus its computed hash.
  const [dup, setDup] = useState<{ file: File; hash: string } | null>(null);

  // Byte-identical + same-name copy already present (ready or still parsing)?
  function findDuplicate(filename: string, hash: string): DocumentRow | undefined {
    return docs.find(
      (d) =>
        d.filename === filename &&
        d.contentHash === hash &&
        (d.status === "ready" || d.status === "parsing"),
    );
  }

  async function doUpload(file: File, contentHash: string) {
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
        contentHash,
      });
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Upload failed");
    } finally {
      setBusy(false);
    }
  }

  async function upload(file: File) {
    const hash = await hashFile(file);
    if (findDuplicate(file.name, hash)) {
      setDup({ file, hash });
      return;
    }
    await doUpload(file, hash);
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
      <DuplicateDialog
        open={dup !== null}
        filename={dup?.file.name ?? ""}
        onOpenChange={(open) => {
          if (!open) setDup(null);
        }}
        onUseExisting={() => {
          setDup(null);
          toast.success("Using your existing copy");
        }}
        onUploadAnyway={() => {
          const pending = dup;
          setDup(null);
          if (pending) void doUpload(pending.file, pending.hash);
        }}
      />
    </div>
  );
}
