import { Loader2 } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { fileIcon, humanSize } from "@/lib/file-icons";

export type Attachment = {
  docId: string;
  filename: string;
  kind: string;
  sizeBytes: number;
};

export type AttachmentStatus = "parsing" | "ready" | "failed";

function StatusPill({ status }: { status: AttachmentStatus }) {
  if (status === "ready") {
    return <Badge variant="success">Ready</Badge>;
  }
  if (status === "failed") {
    return <Badge variant="destructive">Failed</Badge>;
  }
  return (
    <Badge variant="secondary" className="gap-1">
      <Loader2 className="size-3 animate-spin" />
      Parsing…
    </Badge>
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
    <div className="flex items-center gap-2 rounded-md border bg-card px-3 py-2 text-sm">
      <Icon className={`size-5 shrink-0 ${className}`} />
      <div className="min-w-0 flex-1">
        <p className="truncate font-medium text-foreground">{attachment.filename}</p>
        <p className="text-xs text-muted-foreground">{humanSize(attachment.sizeBytes)}</p>
      </div>
      <StatusPill status={status} />
    </div>
  );
}
