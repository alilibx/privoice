import { useEffect, useState } from "react";
import { useQuery, useMutation, useAction } from "convex/react";
import { useUIMessages, useSmoothText } from "@convex-dev/agent/react";
import { api } from "../../convex/_generated/api";

type ThreadRow = {
  _id: string;
  threadId: string;
  title?: string;
  createdAt: number;
};

// Shape returned by useUIMessages's `results` — a superset of UIMessage from
// @convex-dev/agent (role, text, parts, status, key). Kept loose (not the
// exact generic type) so this file doesn't have to fight the agent
// package's UITools/UIDataTypes generics for a simple bubble render.
type ChatMessage = {
  key: string;
  role: string;
  text: string;
  status: string;
  parts: Array<{ type: string; state?: string }>;
};

export default function Chat() {
  const threads = (useQuery(api.chat.listThreads) ?? []) as ThreadRow[];
  const createThread = useMutation(api.chat.createThread);
  const sendMessage = useAction(api.chat.sendMessage);
  const generateUploadUrl = useMutation(api.documents.generateUploadUrl);
  const createDocument = useMutation(api.documents.create);

  const [threadId, setThreadId] = useState<string | null>(null);
  const [text, setText] = useState("");
  const [sending, setSending] = useState(false);
  const [uploadBusy, setUploadBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

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
      await createDocument({
        storageId,
        filename: file.name,
        mimeType: file.type,
        sizeBytes: file.size,
      });
    } catch (e) {
      setError(e instanceof Error ? e.message : "Upload failed");
    } finally {
      setUploadBusy(false);
    }
  }

  return (
    <section className="mx-auto flex h-[calc(100vh-96px)] max-w-4xl gap-4 p-6">
      <aside className="w-56 shrink-0 overflow-y-auto rounded-xl border border-outline bg-surface p-3">
        <button
          onClick={() => void handleNewChat()}
          className="mb-3 w-full rounded-lg bg-primary px-3 py-2 text-sm font-semibold text-white"
        >
          New chat
        </button>
        <ul className="space-y-1">
          {threads.map((t) => (
            <li key={t._id}>
              <button
                onClick={() => setThreadId(t.threadId)}
                aria-current={threadId === t.threadId || undefined}
                className={
                  threadId === t.threadId
                    ? "block w-full truncate rounded-lg bg-primary-container px-3 py-2 text-left text-sm font-medium text-on-primary-container"
                    : "block w-full truncate rounded-lg px-3 py-2 text-left text-sm text-on-surface-variant hover:text-primary"
                }
              >
                {t.title ?? new Date(t.createdAt).toLocaleString()}
              </button>
            </li>
          ))}
          {threads.length === 0 && (
            <li className="px-3 py-2 text-sm text-on-surface-variant">
              No conversations yet.
            </li>
          )}
        </ul>
      </aside>

      <div className="flex flex-1 flex-col rounded-xl border border-outline bg-surface">
        <div className="flex-1 space-y-3 overflow-y-auto p-4">
          {threadId === null && (
            <p className="text-on-surface-variant">
              Start a new chat to ask about your documents and meetings.
            </p>
          )}
          {messages.map((m) => (
            <MessageBubble key={m.key} message={m} />
          ))}
        </div>
        {error && <p className="px-4 pb-2 text-sm text-red-600">{error}</p>}
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

function MessageBubble({ message }: { message: ChatMessage }) {
  const [visibleText] = useSmoothText(message.text, {
    startStreaming: message.status === "streaming",
  });
  const isUser = message.role === "user";
  const pendingTool = (message.parts ?? []).find(
    (p) =>
      p.type.startsWith("tool-") &&
      p.state !== "output-available" &&
      p.state !== "output-error",
  );

  return (
    <div className={isUser ? "flex justify-end" : "flex justify-start"}>
      <div
        className={
          isUser
            ? "max-w-[80%] rounded-xl bg-primary px-4 py-2 text-white"
            : "max-w-[80%] rounded-xl bg-page-bg px-4 py-2 text-on-surface"
        }
      >
        {pendingTool && (
          <p className="mb-1 text-xs italic text-on-surface-variant">
            Searching your documents…
          </p>
        )}
        <p className="whitespace-pre-wrap">{visibleText}</p>
      </div>
    </div>
  );
}

function Composer({
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
    <div className="flex items-end gap-2 border-t border-outline p-3">
      <label className="cursor-pointer rounded-lg px-3 py-2 text-sm font-medium text-on-surface-variant hover:text-primary">
        {uploadBusy ? "Uploading…" : "Attach"}
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
      <textarea
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
        className="flex-1 resize-none rounded-lg border border-outline bg-surface p-2 text-on-surface outline-none focus:border-primary"
      />
      <button
        onClick={onSend}
        disabled={sendDisabled}
        className="rounded-lg bg-primary px-4 py-2 font-semibold text-white disabled:opacity-50"
      >
        Send
      </button>
    </div>
  );
}
