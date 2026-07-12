import { FileText } from "lucide-react";

export type SourceRef = {
  n: number;
  source: string;
  sourceId: string;
  title: string;
  locator: string;
};

const SOURCES_MARKER = "<<<SOURCES>>>";

function isSourceRef(value: unknown): value is SourceRef {
  if (!value || typeof value !== "object") return false;
  const v = value as Record<string, unknown>;
  return typeof v.n === "number" && typeof v.title === "string";
}

// The searchKnowledge tool appends a machine-readable sources block after a
// sentinel marker; the model never sees (or repeats) this JSON tail. Parse it
// defensively — a missing marker or malformed JSON just yields no sources
// rather than breaking the chat.
export function parseSources(toolOutput: string): SourceRef[] {
  const idx = toolOutput.indexOf(SOURCES_MARKER);
  if (idx === -1) return [];
  const jsonText = toolOutput.slice(idx + SOURCES_MARKER.length).trim();
  try {
    const parsed: unknown = JSON.parse(jsonText);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(isSourceRef).map((s) => ({
      n: s.n,
      source: typeof s.source === "string" ? s.source : "",
      sourceId: typeof s.sourceId === "string" ? s.sourceId : "",
      title: s.title,
      locator: typeof s.locator === "string" ? s.locator : "",
    }));
  } catch {
    return [];
  }
}

export default function Sources({ sources }: { sources: SourceRef[] }) {
  if (sources.length === 0) return null;

  return (
    <div className="mt-2 border-t pt-3 text-sm">
      <div className="mb-1.5 flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-muted-foreground">
        <FileText className="h-3.5 w-3.5" />
        Sources
      </div>
      <ol className="space-y-1">
        {sources.map((s) => (
          <li
            key={s.n}
            id={`source-${s.n}`}
            className="flex items-baseline gap-2 leading-relaxed"
          >
            <span className="shrink-0 font-mono text-xs text-muted-foreground">
              [{s.n}]
            </span>
            <span className="text-foreground">{s.title}</span>
            {s.locator && (
              <span className="text-xs text-muted-foreground">· {s.locator}</span>
            )}
          </li>
        ))}
      </ol>
    </div>
  );
}
