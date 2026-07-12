import { useSmoothText } from "@convex-dev/agent/react";
import ToolTrace, { type ToolPart } from "@/features/chat/ToolTrace";
import Markdown from "@/features/chat/Markdown";
import Sources, { parseSources, type SourceRef } from "@/features/chat/Sources";
import AttachmentCard, {
  type Attachment,
  type AttachmentStatus,
} from "@/features/chat/AttachmentCard";
import { displayText } from "@/features/chat/attachment-prompt";
import BrandMark from "@/components/layout/BrandMark";

// searchKnowledge tool outputs carry a trailing <<<SOURCES>>> JSON block; pull
// it out of every matching part so multi-step turns (e.g. search then
// pinpoint) still surface every source that was actually cited.
//
// Each call's SourceRef.n restarts at 1 (see pack.ts's packContext), so
// concatenating sources across multiple tool-searchKnowledge parts in one
// message can produce duplicate `n` values — which would mean duplicate
// `id="source-N"` DOM nodes, duplicate React keys, and an ambiguous
// rendered list. Renumber sequentially across the merged list so `n` is
// unique per rendered message. Note this can't perfectly reconcile the
// agent's [n] markers in the answer text, which still reference each call's
// own per-call numbering — but it guarantees unique DOM ids/keys and a
// coherent Sources list, and a single searchKnowledge call (the common
// case) is unaffected since it's already a no-op renumbering.
function sourcesFromParts(parts: ToolPart[]): SourceRef[] {
  const found: SourceRef[] = [];
  for (const part of parts ?? []) {
    if (part.type !== "tool-searchKnowledge") continue;
    const output = typeof part.output === "string" ? part.output : String(part.output ?? "");
    if (!output) continue;
    found.push(...parseSources(output));
  }
  return found.map((s, i) => ({ ...s, n: i + 1 }));
}

export type ChatMessage = {
  key: string;
  role: string;
  text: string;
  status: string;
  parts: ToolPart[];
};

export default function MessageBubble({
  message,
  attachments,
  statusFor,
}: {
  message: ChatMessage;
  attachments?: Attachment[];
  statusFor?: (docId: string) => AttachmentStatus;
}) {
  const [visibleText] = useSmoothText(message.text, {
    startStreaming: message.status === "streaming",
  });
  const isUser = message.role === "user";
  const hasPendingTool = (message.parts ?? []).some(
    (p) =>
      p.type.startsWith("tool-") &&
      p.state !== "output-available" &&
      p.state !== "output-error",
  );

  // Hide a completed assistant turn that carried only a tool call and no text
  // (an intermediate step) — otherwise it renders as an empty bubble.
  const isEmptyToolTurn =
    !isUser &&
    (message.text ?? "").trim() === "" &&
    message.status !== "streaming" &&
    !hasPendingTool;
  if (isEmptyToolTurn) return null;

  if (isUser) {
    return (
      <div className="msg-in flex flex-col items-end gap-1.5">
        <div className="max-w-[85%] rounded-2xl rounded-br-md bg-primary px-4 py-2.5 text-[15px] leading-relaxed text-primary-foreground shadow-sm sm:max-w-[78%]">
          <p className="whitespace-pre-wrap">{displayText(visibleText)}</p>
        </div>
        {attachments && attachments.length > 0 && (
          <div className="flex flex-wrap justify-end gap-2">
            {attachments.map((a) => (
              <AttachmentCard
                key={a.docId}
                attachment={a}
                status={statusFor?.(a.docId) ?? "ready"}
              />
            ))}
          </div>
        )}
      </div>
    );
  }

  const hasText = (visibleText ?? "").trim() !== "";
  const sources = sourcesFromParts(message.parts);
  return (
    <div className="msg-in flex gap-3 sm:gap-4">
      <BrandMark className="mt-0.5 h-8 w-8 shrink-0" />
      <div className="min-w-0 flex-1 space-y-3">
        <ToolTrace parts={message.parts} />
        {hasText && <Markdown>{visibleText}</Markdown>}
        {sources.length > 0 && <Sources sources={sources} />}
      </div>
    </div>
  );
}
