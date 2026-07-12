import { useEffect, useState } from "react";
import { useQuery, useMutation, useAction } from "convex/react";
import { useUIMessages } from "@convex-dev/agent/react";
import { Link } from "react-router-dom";
import { toast } from "sonner";
import { api } from "../../../convex/_generated/api";
import { MODEL_META, DEFAULT_MODEL } from "../../../convex/models.shared";
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

export default function Chat() {
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
  const [error, setError] = useState<string | null>(null);
  const [attachments, setAttachments] = useState<Attachment[]>([]);

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

  async function handleNewChat() {
    setError(null);
    try {
      const newThreadId = await createThread();
      setThreadId(newThreadId);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to start a new chat");
    }
  }

  async function handleSend() {
    const trimmed = text.trim();
    if (!trimmed || sending) return;
    setText("");
    setPending((p) => [...p, trimmed]); // optimistic echo, instantly
    setSending(true);
    setError(null);
    try {
      // Auto-create a thread on first send (no thread selected yet).
      let tid = threadId;
      if (!tid) {
        tid = await createThread();
        setThreadId(tid);
      }
      await sendMessage({ threadId: tid, text: trimmed });
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to send message");
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
    setError(null);
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
      const message = e instanceof Error ? e.message : "Upload failed";
      setError(message);
      toast.error(message);
    } finally {
      setUploadBusy(false);
    }
  }

  function statusFor(docId: string): "parsing" | "ready" | "failed" {
    const doc = documents.find((d) => d._id === docId);
    return (doc?.status as "parsing" | "ready" | "failed") ?? "parsing";
  }

  return (
    <section className="mx-auto flex h-full max-w-4xl gap-4 p-6">
      <ThreadList
        threads={threads}
        activeThreadId={threadId}
        onSelect={setThreadId}
        onNewChat={() => void handleNewChat()}
      />

      <div className="flex flex-1 flex-col rounded-xl border bg-card">
        <div className="flex items-center justify-between border-b px-4 py-2">
          <span className="text-sm font-medium text-foreground">Chat</span>
          <Link
            to="/settings"
            className="text-xs text-muted-foreground hover:text-foreground hover:underline"
          >
            Model: {modelName}
          </Link>
        </div>
        <div className="flex-1 space-y-3 overflow-y-auto p-4">
          {threadId === null && (
            <p className="text-muted-foreground">
              Start a new chat to ask about your documents and meetings.
            </p>
          )}
          {messages.map((m) => (
            <MessageBubble key={m.key} message={m} />
          ))}
          {pending.map((t, i) => (
            <div key={`pending-${i}`} className="flex justify-end">
              <div className="max-w-[80%] rounded-xl bg-primary px-4 py-2 text-primary-foreground opacity-60">
                <p className="whitespace-pre-wrap">{t}</p>
              </div>
            </div>
          ))}
        </div>
        {attachments.length > 0 && (
          <div className="space-y-2 border-t px-4 py-2">
            {attachments.map((a) => (
              <AttachmentCard key={a.docId} attachment={a} status={statusFor(a.docId)} />
            ))}
          </div>
        )}
        {error && <p className="px-4 pb-2 text-sm text-destructive">{error}</p>}
        <Composer
          text={text}
          onTextChange={setText}
          onSend={() => void handleSend()}
          sendDisabled={sending || text.trim() === ""}
          uploadBusy={uploadBusy}
          onAttach={(f) => void handleAttach(f)}
        />
      </div>
    </section>
  );
}
