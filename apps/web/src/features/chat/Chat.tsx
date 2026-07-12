import { useEffect, useState } from "react";
import { useQuery, useMutation, useAction } from "convex/react";
import { useUIMessages } from "@convex-dev/agent/react";
import { Link } from "react-router-dom";
import { toast } from "sonner";
import { Menu, MessagesSquare } from "lucide-react";
import { api } from "../../../convex/_generated/api";
import { MODEL_META, DEFAULT_MODEL } from "../../../convex/models.shared";
import { useAppShell } from "@/components/layout/app-shell-context";
import BrandMark from "@/components/layout/BrandMark";
import { cn } from "@/lib/utils";
import ThreadList, { type ThreadRow } from "@/features/chat/ThreadList";
import MessageBubble, { type ChatMessage } from "@/features/chat/MessageBubble";
import Composer from "@/features/chat/Composer";
import AttachmentCard, { type Attachment } from "@/features/chat/AttachmentCard";

const KIND_BY_EXT: Record<string, string> = {
  pdf: "pdf",
  docx: "docx",
  xlsx: "xlsx",
  txt: "txt",
  md: "md",
};

function kindFromFilename(filename: string): string {
  const ext = filename.split(".").pop()?.toLowerCase() ?? "";
  return KIND_BY_EXT[ext] ?? ext;
}

const SUGGESTIONS = [
  "Summarize my most recent meeting",
  "What do my documents say about revenue?",
  "List the action items across everything I've uploaded",
];

export default function Chat() {
  const { openNav } = useAppShell();
  const threads = (useQuery(api.chat.listThreads) ?? []) as ThreadRow[];
  const createThread = useMutation(api.chat.createThread);
  const sendMessage = useAction(api.chat.sendMessage);
  const generateUploadUrl = useMutation(api.documents.generateUploadUrl);
  const createDocument = useMutation(api.documents.create);
  const documents = (useQuery(api.documents.list) ?? []) as Array<{
    _id: string;
    status: string;
  }>;
  const modelId = useQuery(api.settings.getSettings)?.modelId ?? DEFAULT_MODEL;
  const modelName =
    MODEL_META[modelId as keyof typeof MODEL_META]?.name ?? modelId;

  const [threadId, setThreadId] = useState<string | null>(null);
  const [text, setText] = useState("");
  const [sending, setSending] = useState(false);
  const [uploadBusy, setUploadBusy] = useState(false);
  const [attachments, setAttachments] = useState<Attachment[]>([]);
  const [railOpen, setRailOpen] = useState(false);

  // Auto-select the most recent thread once the list loads, so the chat
  // opens straight into a conversation instead of an empty picker.
  useEffect(() => {
    if (threadId === null && threads.length > 0) {
      setThreadId(threads[0].threadId);
    }
  }, [threadId, threads]);

  const { results } = useUIMessages(
    api.chat.listMessages,
    threadId ? { threadId } : "skip",
    { initialNumItems: 30, stream: true },
  );
  const messages = results as unknown as ChatMessage[];

  // Optimistic echo: user messages sent this session show instantly, then are
  // dropped once the server-persisted copy appears in `messages`.
  const [pending, setPending] = useState<string[]>([]);
  useEffect(() => {
    setPending((prev) => {
      if (prev.length === 0) return prev;
      const userTexts = messages
        .filter((m) => m.role === "user")
        .map((m) => m.text);
      const next = [...prev];
      for (const t of userTexts) {
        const i = next.indexOf(t);
        if (i >= 0) next.splice(i, 1);
      }
      return next.length === prev.length ? prev : next;
    });
  }, [messages]);
  useEffect(() => {
    setPending([]);
    setAttachments([]);
  }, [threadId]);

  function selectThread(id: string) {
    setThreadId(id);
    setRailOpen(false);
  }

  async function handleNewChat() {
    setRailOpen(false);
    try {
      const newThreadId = await createThread();
      setThreadId(newThreadId);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to start a new chat");
    }
  }

  async function handleSend() {
    const trimmed = text.trim();
    if (!trimmed || sending) return;
    setText("");
    setPending((p) => [...p, trimmed]); // optimistic echo, instantly
    setSending(true);
    try {
      // Auto-create a thread on first send (no thread selected yet).
      let tid = threadId;
      if (!tid) {
        tid = await createThread();
        setThreadId(tid);
      }
      await sendMessage({ threadId: tid, text: trimmed });
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to send message");
      setPending((p) => {
        const i = p.indexOf(trimmed);
        if (i < 0) return p;
        const n = [...p];
        n.splice(i, 1);
        return n;
      });
    } finally {
      setSending(false);
    }
  }

  async function handleAttach(file: File) {
    setUploadBusy(true);
    try {
      const url = await generateUploadUrl();
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": file.type },
        body: file,
      });
      const { storageId } = await res.json();
      const documentId = await createDocument({
        storageId,
        filename: file.name,
        mimeType: file.type,
        sizeBytes: file.size,
      });
      setAttachments((prev) => [
        ...prev,
        {
          docId: documentId as unknown as string,
          filename: file.name,
          kind: kindFromFilename(file.name),
          sizeBytes: file.size,
        },
      ]);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Upload failed");
    } finally {
      setUploadBusy(false);
    }
  }

  function statusFor(docId: string): "parsing" | "ready" | "failed" {
    const doc = documents.find((d) => d._id === docId);
    return (doc?.status as "parsing" | "ready" | "failed") ?? "parsing";
  }

  const activeTitle =
    threads.find((t) => t.threadId === threadId)?.title ?? "New chat";
  const isEmpty = messages.length === 0 && pending.length === 0;

  return (
    <div className="flex h-full min-w-0">
      <ThreadList
        threads={threads}
        activeThreadId={threadId}
        onSelect={selectThread}
        onNewChat={() => void handleNewChat()}
        open={railOpen}
        onClose={() => setRailOpen(false)}
      />

      {/* Scrim for the conversation-rail drawer (mobile). */}
      <div
        aria-hidden
        onClick={() => setRailOpen(false)}
        className={cn(
          "fixed inset-0 z-30 bg-black/40 transition-opacity duration-300 lg:hidden",
          railOpen ? "opacity-100" : "pointer-events-none opacity-0",
        )}
      />

      <div className="chat-canvas relative flex min-w-0 flex-1 flex-col">
        {/* Mobile header */}
        <header className="flex h-14 shrink-0 items-center gap-1 border-b bg-background/70 px-2 backdrop-blur-xl lg:hidden">
          <button
            type="button"
            aria-label="Open menu"
            onClick={openNav}
            className="grid h-10 w-10 place-items-center rounded-lg text-muted-foreground hover:bg-accent hover:text-foreground"
          >
            <Menu className="h-5 w-5" />
          </button>
          <button
            type="button"
            aria-label="Conversations"
            onClick={() => setRailOpen(true)}
            className="grid h-10 w-10 place-items-center rounded-lg text-muted-foreground hover:bg-accent hover:text-foreground"
          >
            <MessagesSquare className="h-5 w-5" />
          </button>
          <h2 className="flex-1 truncate text-center font-display text-base font-semibold">
            {activeTitle}
          </h2>
          <span className="w-10" />
        </header>

        {/* Desktop header */}
        <header className="hidden h-16 shrink-0 items-center justify-between gap-3 border-b bg-background/60 px-6 backdrop-blur-xl lg:flex">
          <h2 className="min-w-0 truncate font-display text-lg font-semibold tracking-tight">
            {activeTitle}
          </h2>
          <Link
            to="/settings"
            className="inline-flex items-center gap-1.5 rounded-full border bg-card/60 px-3 py-1.5 text-xs font-medium text-muted-foreground transition hover:border-primary/40 hover:text-foreground"
          >
            <span className="h-1.5 w-1.5 rounded-full bg-primary" />
            {modelName}
          </Link>
        </header>

        {/* Messages */}
        <div className="flex-1 overflow-y-auto">
          {isEmpty ? (
            <EmptyState onPick={setText} />
          ) : (
            <div className="mx-auto max-w-3xl px-4 py-8 sm:px-6 sm:py-10">
              <div className="space-y-8 sm:space-y-9">
                {messages.map((m) => (
                  <MessageBubble key={m.key} message={m} />
                ))}
                {pending.map((t, i) => (
                  <div key={`pending-${i}`} className="msg-in flex justify-end">
                    <div className="max-w-[85%] rounded-2xl rounded-br-md bg-primary px-4 py-2.5 text-[15px] leading-relaxed text-primary-foreground opacity-60 shadow-sm sm:max-w-[78%]">
                      <p className="whitespace-pre-wrap">{t}</p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Composer */}
        <div className="px-4 pb-4 sm:px-6 sm:pb-6">
          <div className="mx-auto max-w-3xl">
            {attachments.length > 0 && (
              <div className="mb-2 flex flex-wrap gap-2">
                {attachments.map((a) => (
                  <AttachmentCard
                    key={a.docId}
                    attachment={a}
                    status={statusFor(a.docId)}
                  />
                ))}
              </div>
            )}
            <Composer
              text={text}
              onTextChange={setText}
              onSend={() => void handleSend()}
              sendDisabled={sending || text.trim() === ""}
              uploadBusy={uploadBusy}
              onAttach={(f) => void handleAttach(f)}
              modelName={modelName}
            />
            <p className="mt-2 text-center text-[11px] text-muted-foreground">
              Privoice can make mistakes. Answers are grounded in your documents
              and meetings.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}

function EmptyState({ onPick }: { onPick: (text: string) => void }) {
  return (
    <div className="mx-auto flex h-full max-w-2xl flex-col items-center justify-center px-6 py-10 text-center">
      <BrandMark className="h-14 w-14" />
      <h1 className="mt-6 font-display text-3xl font-semibold tracking-tight sm:text-4xl">
        What can I help you find?
      </h1>
      <p className="mt-3 max-w-md text-[15px] leading-relaxed text-muted-foreground">
        Ask anything about your meetings and documents. Privoice searches your
        private knowledge and answers with sources.
      </p>
      <div className="mt-8 grid w-full gap-2 sm:grid-cols-1">
        {SUGGESTIONS.map((s) => (
          <button
            key={s}
            type="button"
            onClick={() => onPick(s)}
            className="rounded-xl border bg-card/60 px-4 py-3 text-left text-sm text-foreground shadow-sm transition hover:border-primary/40 hover:bg-card"
          >
            {s}
          </button>
        ))}
      </div>
    </div>
  );
}
