import { useState } from "react";
import { AlertTriangle, Check, ChevronDown } from "lucide-react";
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

function isRunning(state?: string) {
  return state !== "output-available" && state !== "output-error";
}

function Step({ part }: { part: ToolPart }) {
  const [open, setOpen] = useState(false);
  const query = queryFrom(part.input);
  const output = String(part.output ?? "");
  const hasOutput = output.trim() !== "";
  const running = isRunning(part.state);
  const error = part.state === "output-error";
  const label = labelFor(part.type);

  // Running: a live "thinking" pill with pulsing dots.
  if (running) {
    return (
      <div className="inline-flex items-center gap-2.5 rounded-full border bg-card/60 px-3.5 py-2">
        <span className="flex items-center gap-1">
          <span className="think-dot h-1.5 w-1.5 rounded-full bg-primary" />
          <span className="think-dot h-1.5 w-1.5 rounded-full bg-primary" />
          <span className="think-dot h-1.5 w-1.5 rounded-full bg-primary" />
        </span>
        <span className="text-[13px] font-medium text-muted-foreground">
          {label}
          {query && <span className="text-muted-foreground/80"> · “{query}”</span>}
        </span>
      </div>
    );
  }

  // Completed: a compact disclosure that expands to the tool's result.
  return (
    <div className="w-full overflow-hidden rounded-xl border bg-card/60">
      <button
        type="button"
        onClick={() => hasOutput && setOpen((o) => !o)}
        className={cn(
          "flex w-full items-center gap-2.5 px-3 py-2 text-left",
          hasOutput && "cursor-pointer hover:bg-accent/40",
        )}
      >
        <span
          className={cn(
            "grid h-5 w-5 shrink-0 place-items-center rounded-full",
            error
              ? "bg-destructive/15 text-destructive"
              : "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400",
          )}
        >
          {error ? (
            <AlertTriangle className="h-3 w-3" />
          ) : (
            <Check className="h-3 w-3" strokeWidth={3} />
          )}
        </span>
        <span className="text-[13px] font-medium text-foreground">{label}</span>
        {query && (
          <span className="hidden truncate font-mono text-[12px] text-muted-foreground sm:inline">
            “{query}”
          </span>
        )}
        {hasOutput && (
          <ChevronDown
            className={cn(
              "ml-auto h-4 w-4 shrink-0 text-muted-foreground transition-transform",
              open && "rotate-180",
            )}
          />
        )}
      </button>
      {open && hasOutput && (
        <p className="max-h-48 overflow-y-auto whitespace-pre-wrap border-t bg-background/40 px-3 py-2 font-mono text-[12px] leading-relaxed text-muted-foreground">
          {output.length > 2000 ? `${output.slice(0, 2000)}…` : output}
        </p>
      )}
    </div>
  );
}

export default function ToolTrace({ parts }: { parts: ToolPart[] }) {
  const steps = (parts ?? []).filter((p) => p.type.startsWith("tool-"));
  if (steps.length === 0) return null;

  return (
    <div className="flex flex-col items-start gap-2">
      {steps.map((part, i) => (
        <Step key={`${part.type}-${i}`} part={part} />
      ))}
    </div>
  );
}
