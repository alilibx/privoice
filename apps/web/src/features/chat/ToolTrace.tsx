import { useState } from "react";
import { AlertTriangle, Check, ChevronDown, Loader2 } from "lucide-react";
import { Separator } from "@/components/ui/separator";
import { cn } from "@/lib/utils";

export type ToolPart = {
  type: string;
  state?: string;
  input?: unknown;
  output?: unknown;
};

const LABELS: Record<string, string> = {
  "tool-searchDocuments": "Searched your documents",
  "tool-searchMeetings": "Searched your meetings",
};

function humanizeToolName(type: string) {
  const suffix = type.slice("tool-".length);
  // camelCase -> "search Documents" -> "Search documents"
  const spaced = suffix.replace(/([a-z])([A-Z])/g, "$1 $2");
  return spaced.charAt(0).toUpperCase() + spaced.slice(1).toLowerCase();
}

function labelFor(type: string) {
  return LABELS[type] ?? humanizeToolName(type);
}

function queryFrom(input: unknown): string | undefined {
  if (input && typeof input === "object" && "query" in input) {
    const q = (input as { query?: unknown }).query;
    return typeof q === "string" ? q : undefined;
  }
  return undefined;
}

function StepIcon({ state }: { state?: string }) {
  if (state === "output-available") {
    return <Check className="size-3.5 shrink-0 text-emerald-500" />;
  }
  if (state === "output-error") {
    return <AlertTriangle className="size-3.5 shrink-0 text-destructive" />;
  }
  return <Loader2 className="size-3.5 shrink-0 animate-spin text-muted-foreground" />;
}

function Step({ part }: { part: ToolPart }) {
  const [open, setOpen] = useState(false);
  const query = queryFrom(part.input);
  const output = String(part.output ?? "");
  const hasOutput = output.trim() !== "";

  return (
    <div className="py-1">
      <button
        type="button"
        onClick={() => hasOutput && setOpen((o) => !o)}
        className={cn(
          "flex w-full items-center gap-2 text-left text-xs text-foreground",
          hasOutput && "cursor-pointer",
        )}
      >
        <StepIcon state={part.state} />
        <span className="flex-1">
          {labelFor(part.type)}
          {query && <span className="text-muted-foreground"> &mdash; &ldquo;{query}&rdquo;</span>}
        </span>
        {hasOutput && (
          <ChevronDown className={cn("size-3.5 shrink-0 text-muted-foreground transition-transform", open && "rotate-180")} />
        )}
      </button>
      {open && hasOutput && (
        <p className="mt-1 max-h-40 overflow-y-auto whitespace-pre-wrap rounded-md bg-background/60 p-2 text-xs text-muted-foreground">
          {output.length > 2000 ? `${output.slice(0, 2000)}…` : output}
        </p>
      )}
    </div>
  );
}

export default function ToolTrace({ parts }: { parts: ToolPart[] }) {
  const steps = (parts ?? []).filter((p) => p.type.startsWith("tool-"));
  if (steps.length === 0) return null;

  const stillRunning = steps.some(
    (s) => s.state !== "output-available" && s.state !== "output-error",
  );

  return (
    <div className="mb-2 rounded-md border bg-muted/50 px-3 py-2">
      <p className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
        {stillRunning ? "Thinking" : "Activity"}
      </p>
      <Separator className="my-1" />
      <div>
        {steps.map((part, i) => (
          <Step key={`${part.type}-${i}`} part={part} />
        ))}
      </div>
    </div>
  );
}
