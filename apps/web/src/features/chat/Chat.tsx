import { useEffect, useState } from "react";
import { useQuery, useMutation, useAction } from "convex/react";
import { useUIMessages } from "@convex-dev/agent/react";
import { Link } from "react-router-dom";
import { toast } from "sonner";
import { Menu, MessagesSquare, PanelLeft, ArrowDown } from "lucide-react";
import { api } from "../../../convex/_generated/api";
import { MODEL_META, DEFAULT_MODEL } from "../../../convex/models.shared";
import { useAppShell } from "@/components/layout/app-shell-context";
import BrandMark from "@/components/layout/BrandMark";
import { cn } from "@/lib/utils";
import ThreadList, { type ThreadRow } from "@/features/chat/ThreadList";
import MessageBubble, { type ChatMessage } from "@/features/chat/MessageBubble";
import Composer from "@/features/chat/Composer";
import AttachmentCard, {
  type Attachment,
  type AttachmentStatus,
} from "@/features/chat/AttachmentCard";
import { withAttachmentContext, displayText } from "@/features/chat/attachment-prompt";
import { useStickToBottom } from "@/features/chat/use-stick-to-bottom";
import DuplicateDialog from "@/features/documents/DuplicateDialog";
import { hashFile } from "@/features/documents/content-hash";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";

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

const RAIL_HIDE_KEY = "privoice-rail-hidden";

type PendingEcho = { text: string; attachments: Attachment[] };

export default function Chat() {
  const { openNav, toggleDesktopNav, desktopNavHidden } = useAppShell();
  const threads = (useQuery(api.chat.listThreads) ?? []) as ThreadRow[];
  const createThread = useMutation(api.chat.createThread);
  const deleteThread = useMutation(api.chat.deleteThread);
  const sendMessage = useAction(api.chat.sendMessage);
  const generateUploadUrl = useMutation(api.documents.generateUploadUrl);
  const createDocument = useMutation(api.documents.create);
  const documents = (useQuery(api.documents.list) ?? []) as Array<{
    _id: string;
    filename: string;
    kind: string;
    sizeBytes: number;
    status: string;
    contentHash?: string;
  }>;
  const modelId = useQuery(api.settings.getSettings)?.modelId ?? DEFAULT_MODEL;
  const modelName =
    MODEL_META[modelId as keyof typeof MODEL_META]?.name ?? modelId;

  const [threadId, setThreadId] = useState<string | null>(null);
  const [text, setText] = useState("");
  const [sending, setSending] = useState(false);
  const [uploadBusy, setUploadBusy] = useState(false);
  // Files attached to the message currently being composed (not yet sent).
  const [pendingAttachments, setPendingAttachments] = useState<Attachment[]>([]);
  // A chat attachment awaiting a duplicate decision (same name + same bytes).
  const [attachDup, setAttachDup] = useState<{ file: File; hash: string } | null>(null);
  // The threadId awaiting delete confirmation.
  const [pendingDelete, setPendingDelete] = useState<string | null>(null);
  // Attachments that were sent with a message, keyed by the message text, so
  // the chips render under the right user turn in the transcript (session-only;
  // the server transcript doesn't carry attachment metadata).
  const [sentAttachments, setSentAttachments] = useState<
    { text: string; attachments: Attachment[] }[]
  >([]);
  const [railOpen, setRailOpen] = useState(false);
  const [railHidden, setRailHidden] = useState(
    () => typeof localStorage !== "undefined" && localStorage.getItem(RAIL_HIDE_KEY) === "1",
  );

  const {
    ref: scrollRef,
    atBottom,
    onScroll,
    scrollToBottom,
    stick,
  } = useStickToBottom<HTMLDivElement>();

  function toggleRail() {
    setRailHidden((prev) => {
      const next = !prev;
      localStorage.setItem(RAIL_HIDE_KEY, next ? "1" : "0");
      return next;
    });
  }

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
  // dropped once the server-persisted copy appears (matched on the visible
  // text, since the persisted prompt may carry an appended grounding note).
  const [pending, setPending] = useState<PendingEcho[]>([]);
  useEffect(() => {
    setPending((prev) => {
      if (prev.length === 0) return prev;
      const userTexts = messages
        .filter((m) => m.role === "user")
        .map((m) => displayText(m.text));
      const next = [...prev];
      for (const t of userTexts) {
        const i = next.findIndex((p) => p.text === t);
        if (i >= 0) next.splice(i, 1);
      }
      return next.length === prev.length ? prev : next;
    });
  }, [messages]);
  useEffect(() => {
    setPending([]);
    setPendingAttachments([]);
    setSentAttachments([]);
    setAttachDup(null);
    scrollToBottom("auto");
  }, [threadId, scrollToBottom]);

  // Follow the conversation as it grows/streams — but only if the user is
  // already at the bottom (stick() gates on that). handleSend force-scrolls
  // separately, so a send always lands at the latest.
  useEffect(() => {
    stick();
  }, [messages, pending, stick]);

  function statusFor(docId: string): AttachmentStatus {
    const doc = documents.find((d) => d._id === docId);
    return (doc?.status as AttachmentStatus) ?? "parsing";
  }

  // Block sending while an attachment is still loading (uploading/ingesting) —
  // the document must be searchable before the assistant can ground on it.
  const attachmentsLoading = pendingAttachments.some(
    (a) => statusFor(a.docId) === "parsing",
  );

  function attachmentsForText(t: string): Attachment[] | undefined {
    return sentAttachments.find((s) => s.text === t)?.attachments;
  }

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

  async function confirmDelete() {
    const id = pendingDelete;
    setPendingDelete(null);
    if (!id) return;
    try {
      await deleteThread({ threadId: id });
      if (id === threadId) {
        // Re-select the most recent remaining thread (threads is desc-ordered),
        // or fall to the empty state when none remain.
        const next = threads.find((t) => t.threadId !== id);
        setThreadId(next ? next.threadId : null);
      }
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to delete conversation");
    }
  }

  async function handleSend() {
    const trimmed = text.trim();
    if (!trimmed || sending || attachmentsLoading) return;

    const atts = pendingAttachments;
    setText("");
    setPendingAttachments([]);
    setPending((p) => [...p, { text: trimmed, attachments: atts }]); // optimistic
    // The user's own send always jumps to the latest, even if they'd scrolled
    // up. rAF lets the optimistic bubble paint first so scrollHeight is final.
    requestAnimationFrame(() => scrollToBottom("auto"));
    if (atts.length > 0) {
      setSentAttachments((s) => [...s, { text: trimmed, attachments: atts }]);
    }
    setSending(true);
    try {
      // Auto-create a thread on first send (no thread selected yet).
      let tid = threadId;
      if (!tid) {
        tid = await createThread();
        setThreadId(tid);
      }
      // Append a grounding note naming the attached files so the assistant
      // answers about them (stripped from the visible bubble by displayText).
      const prompt = withAttachmentContext(
        trimmed,
        atts.map((a) => a.filename),
      );
      await sendMessage({
        threadId: tid,
        text: prompt,
        pinnedSourceIds: atts.map((a) => a.docId),
      });
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to send message");
      setPending((p) => {
        const i = p.findIndex((x) => x.text === trimmed);
        if (i < 0) return p;
        const n = [...p];
        n.splice(i, 1);
        return n;
      });
    } finally {
      setSending(false);
    }
  }

  async function doAttachUpload(file: File, contentHash: string) {
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
        contentHash,
      });
      setPendingAttachments((prev) => [
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

  // Attach the already-uploaded document (no new copy) — the "reference the
  // existing document" path when the user confirms a duplicate.
  function attachExisting(docId: string) {
    const doc = documents.find((d) => d._id === docId);
    if (!doc) return;
    setPendingAttachments((prev) =>
      prev.some((a) => a.docId === docId)
        ? prev
        : [
            ...prev,
            {
              docId: doc._id,
              filename: doc.filename,
              kind: doc.kind || kindFromFilename(doc.filename),
              sizeBytes: doc.sizeBytes,
            },
          ],
    );
  }

  async function handleAttach(file: File) {
    const hash = await hashFile(file);
    const existing = documents.find(
      (d) =>
        d.filename === file.name &&
        d.contentHash === hash &&
        (d.status === "ready" || d.status === "parsing"),
    );
    if (existing) {
      setAttachDup({ file, hash });
      return;
    }
    await doAttachUpload(file, hash);
  }

  function removePendingAttachment(docId: string) {
    setPendingAttachments((prev) => prev.filter((a) => a.docId !== docId));
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
        desktopHidden={railHidden}
        onClose={() => setRailOpen(false)}
        onCollapse={toggleRail}
        onDelete={(id) => setPendingDelete(id)}
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
        <header className="hidden h-16 shrink-0 items-center justify-between gap-3 border-b bg-background/60 px-4 backdrop-blur-xl lg:flex">
          <div className="flex min-w-0 items-center gap-1">
            {desktopNavHidden && (
              <button
                type="button"
                aria-label="Show sidebar"
                title="Show sidebar"
                onClick={toggleDesktopNav}
                className="grid h-9 w-9 shrink-0 place-items-center rounded-lg text-muted-foreground hover:bg-accent hover:text-foreground"
              >
                <PanelLeft className="h-[18px] w-[18px]" />
              </button>
            )}
            <button
              type="button"
              aria-label={railHidden ? "Show conversations" : "Hide conversations"}
              title={railHidden ? "Show conversations" : "Hide conversations"}
              onClick={toggleRail}
              className={cn(
                "grid h-9 w-9 shrink-0 place-items-center rounded-lg hover:bg-accent hover:text-foreground",
                railHidden ? "text-muted-foreground" : "text-foreground",
              )}
            >
              <MessagesSquare className="h-[18px] w-[18px]" />
            </button>
            <h2 className="min-w-0 truncate pl-1 font-display text-lg font-semibold tracking-tight">
              {activeTitle}
            </h2>
          </div>
          <Link
            to="/settings"
            className="inline-flex items-center gap-1.5 rounded-full border bg-card/60 px-3 py-1.5 text-xs font-medium text-muted-foreground transition hover:border-primary/40 hover:text-foreground"
          >
            <span className="h-1.5 w-1.5 rounded-full bg-primary" />
            {modelName}
          </Link>
        </header>

        {/* Messages */}
        <div ref={scrollRef} onScroll={onScroll} className="flex-1 overflow-y-auto">
          {isEmpty ? (
            <EmptyState onPick={setText} />
          ) : (
            <div className="mx-auto max-w-3xl px-4 py-8 sm:px-6 sm:py-10">
              <div className="space-y-8 sm:space-y-9">
                {messages.map((m) => (
                  <MessageBubble
                    key={m.key}
                    message={m}
                    attachments={
                      m.role === "user"
                        ? attachmentsForText(displayText(m.text))
                        : undefined
                    }
                    statusFor={statusFor}
                  />
                ))}
                {pending.map((p, i) => (
                  <div
                    key={`pending-${i}`}
                    className="msg-in flex flex-col items-end gap-1.5"
                  >
                    <div className="max-w-[85%] rounded-2xl rounded-br-md bg-primary px-4 py-2.5 text-[15px] leading-relaxed text-primary-foreground opacity-70 shadow-sm sm:max-w-[78%]">
                      <p className="whitespace-pre-wrap">{p.text}</p>
                    </div>
                    {p.attachments.length > 0 && (
                      <div className="flex flex-wrap justify-end gap-2">
                        {p.attachments.map((a) => (
                          <AttachmentCard
                            key={a.docId}
                            attachment={a}
                            status={statusFor(a.docId)}
                          />
                        ))}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        {!atBottom && !isEmpty && (
          <button
            type="button"
            onClick={() => scrollToBottom("smooth")}
            className="absolute bottom-28 left-1/2 z-10 -translate-x-1/2 inline-flex items-center gap-1.5 rounded-full border bg-card/90 px-3 py-1.5 text-xs font-medium text-foreground shadow-md backdrop-blur transition hover:border-primary/40"
          >
            Jump to latest
            <ArrowDown className="h-3.5 w-3.5" />
          </button>
        )}

        {/* Composer */}
        <div className="px-4 pb-4 sm:px-6 sm:pb-6">
          <div className="mx-auto max-w-3xl">
            {pendingAttachments.length > 0 && (
              <div className="mb-2 flex flex-wrap gap-2">
                {pendingAttachments.map((a) => (
                  <AttachmentCard
                    key={a.docId}
                    attachment={a}
                    status={statusFor(a.docId)}
                    onRemove={() => removePendingAttachment(a.docId)}
                  />
                ))}
              </div>
            )}
            <Composer
              text={text}
              onTextChange={setText}
              onSend={() => void handleSend()}
              sendDisabled={sending || text.trim() === "" || attachmentsLoading}
              uploadBusy={uploadBusy}
              onAttach={(f) => void handleAttach(f)}
              modelName={modelName}
            />
            <p className="mt-2 text-center text-[11px] text-muted-foreground">
              {attachmentsLoading
                ? "Waiting for the attachment to finish loading…"
                : "Privoice can make mistakes. Answers are grounded in your documents and meetings."}
            </p>
          </div>
        </div>
      </div>

      <DuplicateDialog
        open={attachDup !== null}
        filename={attachDup?.file.name ?? ""}
        onOpenChange={(open) => {
          if (!open) setAttachDup(null);
        }}
        onUseExisting={() => {
          const pending = attachDup;
          setAttachDup(null);
          if (pending) {
            const existing = documents.find(
              (d) =>
                d.filename === pending.file.name && d.contentHash === pending.hash,
            );
            if (existing) attachExisting(existing._id);
          }
        }}
        onUploadAnyway={() => {
          const pending = attachDup;
          setAttachDup(null);
          if (pending) void doAttachUpload(pending.file, pending.hash);
        }}
      />

      <Dialog
        open={pendingDelete !== null}
        onOpenChange={(open) => {
          if (!open) setPendingDelete(null);
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete conversation</DialogTitle>
            <DialogDescription>
              This conversation and its messages will be permanently deleted.
              This can&apos;t be undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setPendingDelete(null)}>
              Cancel
            </Button>
            <Button variant="destructive" onClick={() => void confirmDelete()}>
              Delete
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
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
