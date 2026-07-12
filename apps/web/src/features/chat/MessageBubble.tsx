import { useSmoothText } from "@convex-dev/agent/react";
import ToolTrace, { type ToolPart } from "@/features/chat/ToolTrace";
import Markdown from "@/features/chat/Markdown";
import AttachmentCard, {
  type Attachment,
  type AttachmentStatus,
} from "@/features/chat/AttachmentCard";
import { displayText } from "@/features/chat/attachment-prompt";
import BrandMark from "@/components/layout/BrandMark";

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
  return (
    <div className="msg-in flex gap-3 sm:gap-4">
      <BrandMark className="mt-0.5 h-8 w-8 shrink-0" />
      <div className="min-w-0 flex-1 space-y-3">
        <ToolTrace parts={message.parts} />
        {hasText && <Markdown>{visibleText}</Markdown>}
      </div>
    </div>
  );
}
