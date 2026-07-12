import { useSmoothText } from "@convex-dev/agent/react";
import ToolTrace, { type ToolPart } from "@/features/chat/ToolTrace";
import { cn } from "@/lib/utils";

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

  return (
    <div className={isUser ? "flex justify-end" : "flex justify-start"}>
      <div className={cn("max-w-[80%]", !isUser && "w-full")}>
        {!isUser && <ToolTrace parts={message.parts} />}
        <div
          className={cn(
            "rounded-xl px-4 py-2",
            isUser
              ? "bg-primary text-primary-foreground"
              : "bg-muted text-foreground",
          )}
        >
          <p className="whitespace-pre-wrap">{visibleText}</p>
        </div>
      </div>
    </div>
  );
}
