import { Loader2, Paperclip, Send } from "lucide-react";
import { Button, buttonVariants } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";

export default function Composer({
  text,
  onTextChange,
  onSend,
  sendDisabled,
  uploadBusy,
  onAttach,
}: {
  text: string;
  onTextChange: (v: string) => void;
  onSend: () => void;
  sendDisabled: boolean;
  uploadBusy: boolean;
  onAttach: (file: File) => void;
}) {
  return (
    <div className="flex items-end gap-2 border-t p-3">
      <label
        className={cn(
          buttonVariants({ variant: "ghost", size: "icon" }),
          "cursor-pointer",
          uploadBusy && "pointer-events-none opacity-50",
        )}
      >
        {uploadBusy ? (
          <Loader2 className="size-4 animate-spin" />
        ) : (
          <Paperclip className="size-4" />
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
      <Textarea
        value={text}
        onChange={(e) => onTextChange(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "Enter" && !e.shiftKey) {
            e.preventDefault();
            onSend();
          }
        }}
        placeholder="Ask about your documents or meetings…"
        rows={2}
        className="flex-1 resize-none"
      />
      <Button onClick={onSend} disabled={sendDisabled} size="icon" aria-label="Send">
        <Send className="size-4" />
      </Button>
    </div>
  );
}
