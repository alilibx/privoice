import { Loader2 } from "lucide-react";
import { fileIcon, humanSize } from "@/lib/file-icons";
import { cn } from "@/lib/utils";

export type Attachment = {
  docId: string;
  filename: string;
  kind: string;
  sizeBytes: number;
};

export type AttachmentStatus = "parsing" | "ready" | "failed";

function StatusPill({ status }: { status: AttachmentStatus }) {
  if (status === "ready") {
    return (
      <span className="inline-flex items-center rounded-full bg-emerald-500/15 px-2 py-0.5 text-[11px] font-semibold text-emerald-600 dark:text-emerald-400">
        Ready
      </span>
    );
  }
  if (status === "failed") {
    return (
      <span className="inline-flex items-center rounded-full bg-destructive/15 px-2 py-0.5 text-[11px] font-semibold text-destructive">
        Failed
      </span>
    );
  }
  return (
    <span className="inline-flex items-center gap-1 rounded-full bg-muted px-2 py-0.5 text-[11px] font-semibold text-muted-foreground">
      <Loader2 className="h-3 w-3 animate-spin" />
      Parsing…
    </span>
  );
}

export default function AttachmentCard({
  attachment,
  status,
}: {
  attachment: Attachment;
  status: AttachmentStatus;
}) {
  const { Icon, className } = fileIcon(attachment.kind);
  return (
    <div className="inline-flex items-center gap-2 rounded-xl border bg-card px-2.5 py-1.5 text-sm shadow-sm">
      <Icon className={cn("h-4 w-4 shrink-0", className)} />
      <span className="max-w-[160px] truncate font-medium text-foreground">
        {attachment.filename}
      </span>
      <span className="text-xs text-muted-foreground">{humanSize(attachment.sizeBytes)}</span>
      <StatusPill status={status} />
    </div>
  );
}
