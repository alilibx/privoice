import { Plus, X } from "lucide-react";
import { cn } from "@/lib/utils";

export type ThreadRow = {
  _id: string;
  threadId: string;
  title?: string;
  createdAt: number;
};

function relativeDay(ts: number): string {
  const d = new Date(ts);
  const now = new Date();
  const sameDay = d.toDateString() === now.toDateString();
  if (sameDay) return d.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
  return d.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

/**
 * The conversation rail. Static column on `lg+`, off-canvas drawer (translated
 * by `open`) below. `onClose` backs the drawer's close button on small screens.
 */
export default function ThreadList({
  threads,
  activeThreadId,
  onSelect,
  onNewChat,
  open,
  onClose,
}: {
  threads: ThreadRow[];
  activeThreadId: string | null;
  onSelect: (threadId: string) => void;
  onNewChat: () => void;
  open: boolean;
  onClose: () => void;
}) {
  return (
    <div
      className={cn(
        "fixed inset-y-0 left-0 z-40 flex w-[288px] flex-col border-r bg-background transition-transform duration-300 ease-out",
        "lg:static lg:z-auto lg:w-72 lg:translate-x-0 lg:bg-background/40 lg:shadow-none",
        open ? "translate-x-0 shadow-2xl" : "-translate-x-full",
      )}
    >
      <div className="flex items-center gap-2 p-3">
        <button
          type="button"
          onClick={onNewChat}
          className="flex flex-1 items-center justify-center gap-2 rounded-xl bg-primary px-4 py-2.5 text-sm font-semibold text-primary-foreground shadow-sm transition hover:bg-primary/90"
        >
          <Plus className="h-4 w-4" strokeWidth={2.4} />
          New chat
        </button>
        <button
          type="button"
          aria-label="Close conversations"
          onClick={onClose}
          className="grid h-10 w-10 shrink-0 place-items-center rounded-xl border text-muted-foreground hover:bg-accent lg:hidden"
        >
          <X className="h-4 w-4" />
        </button>
      </div>

      <div className="flex-1 overflow-y-auto px-2 pb-3">
        {threads.length === 0 ? (
          <p className="px-3 py-6 text-center text-sm text-muted-foreground">
            No conversations yet.
          </p>
        ) : (
          <ul className="space-y-0.5">
            {threads.map((t) => {
              const active = activeThreadId === t.threadId;
              return (
                <li key={t._id}>
                  <button
                    type="button"
                    onClick={() => onSelect(t.threadId)}
                    aria-current={active || undefined}
                    className={cn(
                      "relative flex w-full flex-col gap-0.5 rounded-lg px-3 py-2 text-left transition-colors",
                      active ? "bg-accent/70" : "hover:bg-accent/50",
                    )}
                  >
                    {active && (
                      <span className="absolute inset-y-2 left-0 w-[3px] rounded-r bg-primary" />
                    )}
                    <span
                      className={cn(
                        "truncate text-sm font-medium",
                        active ? "text-accent-foreground" : "text-foreground",
                      )}
                    >
                      {t.title ?? "New conversation"}
                    </span>
                    <span className="truncate text-xs text-muted-foreground">
                      {relativeDay(t.createdAt)}
                    </span>
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </div>
  );
}
