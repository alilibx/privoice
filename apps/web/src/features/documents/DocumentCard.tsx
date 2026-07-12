import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { fileIcon, humanSize } from "@/lib/file-icons";
import StatusBadge from "@/features/documents/StatusBadge";

export type DocumentRow = {
  _id: string;
  filename: string;
  kind: string;
  sizeBytes: number;
  status: string;
  chunkCount: number;
  error?: string;
  contentHash?: string;
};

export default function DocumentCard({
  doc,
  onDelete,
}: {
  doc: DocumentRow;
  onDelete: (id: string) => void;
}) {
  const { Icon, className } = fileIcon(doc.kind);
  return (
    <Card>
      <CardContent className="flex items-center gap-3 p-4">
        <Icon className={`size-8 shrink-0 ${className}`} />
        <div className="min-w-0 flex-1">
          <p className="truncate font-medium text-foreground">{doc.filename}</p>
          <div className="mt-1 flex items-center gap-2">
            <span className="text-xs text-muted-foreground">{humanSize(doc.sizeBytes)}</span>
            <StatusBadge status={doc.status} chunkCount={doc.chunkCount} error={doc.error} />
          </div>
        </div>
        <Button
          variant="ghost"
          size="icon"
          aria-label="Delete document"
          onClick={() => onDelete(doc._id)}
        >
          <Trash2 className="size-4" />
        </Button>
      </CardContent>
    </Card>
  );
}
