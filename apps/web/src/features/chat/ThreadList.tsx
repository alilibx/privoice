import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { cn } from "@/lib/utils";

export type ThreadRow = {
  _id: string;
  threadId: string;
  title?: string;
  createdAt: number;
};

export default function ThreadList({
  threads,
  activeThreadId,
  onSelect,
  onNewChat,
}: {
  threads: ThreadRow[];
  activeThreadId: string | null;
  onSelect: (threadId: string) => void;
  onNewChat: () => void;
}) {
  return (
    <aside className="flex w-56 shrink-0 flex-col rounded-xl border bg-card p-3">
      <Button onClick={onNewChat} className="mb-3 w-full" size="sm">
        New chat
      </Button>
      <ScrollArea className="flex-1">
        <ul className="space-y-1 pr-2">
          {threads.map((t) => (
            <li key={t._id}>
              <Button
                variant="ghost"
                onClick={() => onSelect(t.threadId)}
                aria-current={activeThreadId === t.threadId || undefined}
                className={cn(
                  "w-full justify-start truncate font-normal",
                  activeThreadId === t.threadId && "bg-accent text-accent-foreground",
                )}
              >
                {t.title ?? new Date(t.createdAt).toLocaleString()}
              </Button>
            </li>
          ))}
          {threads.length === 0 && (
            <li className="px-3 py-2 text-sm text-muted-foreground">
              No conversations yet.
            </li>
          )}
        </ul>
      </ScrollArea>
    </aside>
  );
}
