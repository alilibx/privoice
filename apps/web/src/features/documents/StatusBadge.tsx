import { Badge } from "@/components/ui/badge";

export default function StatusBadge({
  status,
  chunkCount,
  error,
}: {
  status: string;
  chunkCount: number;
  error?: string;
}) {
  if (status === "ready") {
    return <Badge variant="success">Ready · {chunkCount} chunks</Badge>;
  }
  if (status === "failed") {
    return (
      <Badge variant="destructive" title={error}>
        Failed
      </Badge>
    );
  }
  return <Badge variant="secondary">Parsing…</Badge>;
}
