import { File, FileSpreadsheet, FileText, FileType2, type LucideIcon } from "lucide-react";

const ICON_BY_KIND: Record<string, { Icon: LucideIcon; className: string }> = {
  pdf: { Icon: FileText, className: "text-red-500" },
  txt: { Icon: FileText, className: "text-muted-foreground" },
  md: { Icon: FileText, className: "text-muted-foreground" },
  docx: { Icon: FileType2, className: "text-blue-500" },
  xlsx: { Icon: FileSpreadsheet, className: "text-emerald-500" },
};

export function fileIcon(kind: string): { Icon: LucideIcon; className: string } {
  return ICON_BY_KIND[kind] ?? { Icon: File, className: "text-muted-foreground" };
}

export function humanSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  const kb = bytes / 1024;
  if (kb < 1024) return `${kb % 1 === 0 ? kb.toFixed(0) : kb.toFixed(1)} KB`;
  const mb = kb / 1024;
  return `${mb % 1 === 0 ? mb.toFixed(0) : mb.toFixed(1)} MB`;
}
