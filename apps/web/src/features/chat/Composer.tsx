import { useEffect, useRef } from "react";
import { Loader2, Paperclip, ArrowUp } from "lucide-react";

export default function Composer({
  text,
  onTextChange,
  onSend,
  sendDisabled,
  uploadBusy,
  onAttach,
  modelName,
}: {
  text: string;
  onTextChange: (v: string) => void;
  onSend: () => void;
  sendDisabled: boolean;
  uploadBusy: boolean;
  onAttach: (file: File) => void;
  modelName?: string;
}) {
  const ref = useRef<HTMLTextAreaElement>(null);

  // Auto-grow the textarea up to its max-height, then let it scroll.
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${Math.min(el.scrollHeight, 176)}px`;
  }, [text]);

  return (
    <div className="composer-card rounded-[24px] border bg-card p-2 transition focus-within:ring-2 focus-within:ring-primary/60">
      <textarea
        ref={ref}
        value={text}
        onChange={(e) => onTextChange(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "Enter" && !e.shiftKey) {
            e.preventDefault();
            onSend();
          }
        }}
        placeholder="Ask about your documents or meetings…"
        rows={1}
        className="block max-h-44 w-full resize-none bg-transparent px-3 py-2.5 text-[15px] leading-6 text-foreground outline-none placeholder:text-muted-foreground"
      />
      <div className="flex items-center gap-1.5 px-1 pb-0.5 pt-1">
        <label
          className={`grid h-9 w-9 cursor-pointer place-items-center rounded-full text-muted-foreground transition hover:bg-accent hover:text-foreground ${uploadBusy ? "pointer-events-none opacity-50" : ""}`}
          title="Attach a document"
        >
          {uploadBusy ? (
            <Loader2 className="h-[18px] w-[18px] animate-spin" />
          ) : (
            <Paperclip className="h-[18px] w-[18px]" />
          )}
          <input
            type="file"
            aria-label="Attach a document"
            accept=".pdf,.docx,.xlsx,.txt,.md"
            className="hidden"
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) onAttach(f);
              e.target.value = "";
            }}
          />
        </label>
        {modelName && (
          <span className="hidden truncate text-xs text-muted-foreground sm:inline">
            {modelName}
          </span>
        )}
        <span className="ml-auto hidden text-[11px] text-muted-foreground sm:inline">
          ↵ to send&nbsp;&nbsp;·&nbsp;&nbsp;⇧↵ new line
        </span>
        <button
          type="button"
          onClick={onSend}
          disabled={sendDisabled}
          aria-label="Send"
          className="ml-auto grid h-9 w-9 place-items-center rounded-full bg-primary text-primary-foreground shadow-sm transition hover:bg-primary/90 disabled:opacity-40 sm:ml-0"
        >
          <ArrowUp className="h-[18px] w-[18px]" strokeWidth={2.4} />
        </button>
      </div>
    </div>
  );
}
