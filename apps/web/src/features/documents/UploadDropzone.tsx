import { useRef, useState } from "react";
import { Loader2, UploadCloud } from "lucide-react";
import { cn } from "@/lib/utils";

export default function UploadDropzone({
  onFile,
  busy,
}: {
  onFile: (file: File) => void;
  busy: boolean;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [dragOver, setDragOver] = useState(false);

  function handleFiles(files: FileList | null) {
    const file = files?.[0];
    if (file) onFile(file);
  }

  return (
    <div
      role="button"
      tabIndex={0}
      aria-label="Upload a document"
      onClick={() => !busy && inputRef.current?.click()}
      onKeyDown={(e) => {
        if (!busy && (e.key === "Enter" || e.key === " ")) {
          e.preventDefault();
          inputRef.current?.click();
        }
      }}
      onDragOver={(e) => {
        e.preventDefault();
        if (!busy) setDragOver(true);
      }}
      onDragLeave={() => setDragOver(false)}
      onDrop={(e) => {
        e.preventDefault();
        setDragOver(false);
        if (!busy) handleFiles(e.dataTransfer.files);
      }}
      className={cn(
        "flex cursor-pointer flex-col items-center justify-center gap-2 rounded-xl border-2 border-dashed border-muted-foreground/30 bg-card p-8 text-center transition-colors",
        dragOver && "border-primary bg-accent",
        busy && "pointer-events-none opacity-60",
      )}
    >
      {busy ? (
        <Loader2 className="size-6 animate-spin text-muted-foreground" />
      ) : (
        <UploadCloud className="size-6 text-muted-foreground" />
      )}
      <p className="text-sm text-muted-foreground">
        {busy ? "Uploading…" : "Drop a file here, or click to browse"}
      </p>
      <p className="text-xs text-muted-foreground/70">PDF, Word, Excel, txt, md</p>
      <input
        ref={inputRef}
        type="file"
        aria-hidden="true"
        tabIndex={-1}
        accept=".pdf,.docx,.xlsx,.txt,.md"
        className="hidden"
        onChange={(e) => {
          handleFiles(e.target.files);
          e.target.value = "";
        }}
      />
    </div>
  );
}
