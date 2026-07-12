import { useSmoothText } from "@convex-dev/agent/react";
import ToolTrace, { type ToolPart } from "@/features/chat/ToolTrace";
import BrandMark from "@/components/layout/BrandMark";

export type ChatMessage = {
  key: string;
  role: string;
  text: string;
  status: string;
  parts: ToolPart[];
};

export default function MessageBubble({ message }: { message: ChatMessage }) {
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
      <div className="msg-in flex justify-end">
        <div className="max-w-[85%] rounded-2xl rounded-br-md bg-primary px-4 py-2.5 text-[15px] leading-relaxed text-primary-foreground shadow-sm sm:max-w-[78%]">
          <p className="whitespace-pre-wrap">{visibleText}</p>
        </div>
      </div>
    );
  }

  const hasText = (visibleText ?? "").trim() !== "";
  return (
    <div className="msg-in flex gap-3 sm:gap-4">
      <BrandMark className="mt-0.5 h-8 w-8 shrink-0" />
      <div className="min-w-0 flex-1 space-y-3">
        <ToolTrace parts={message.parts} />
        {hasText && (
          <div className="whitespace-pre-wrap text-[15px] leading-7 text-foreground">
            {visibleText}
          </div>
        )}
      </div>
    </div>
  );
}
