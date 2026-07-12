import { useQuery, useMutation } from "convex/react";
import { toast } from "sonner";
import { api } from "../../../convex/_generated/api";
import type { Id } from "../../../convex/_generated/dataModel";
import MeetingCard, { type Meeting } from "@/features/meetings/MeetingCard";
import NewMeetingDialog from "@/features/meetings/NewMeetingDialog";

export default function MeetingsList() {
  const meetings = (useQuery(api.meetings.list) ?? []) as Meeting[];
  const create = useMutation(api.meetings.create);
  const remove = useMutation(api.meetings.remove);

  async function handleCreate(title: string) {
    try {
      await create({ title, notes: undefined });
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to create meeting");
    }
  }

  async function handleDelete(id: string) {
    try {
      await remove({ id: id as Id<"meetings"> });
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to delete meeting");
    }
  }

  return (
    <main className="mx-auto max-w-3xl p-6">
      <header className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-foreground">Meetings</h1>
        <NewMeetingDialog onCreate={handleCreate} />
      </header>

      {meetings.length === 0 ? (
        <p className="mt-8 text-center text-muted-foreground">No meetings yet</p>
      ) : (
        <div className="mt-6 grid grid-cols-1 gap-3 sm:grid-cols-2">
          {meetings.map((m) => (
            <MeetingCard key={m._id} meeting={m} onDelete={(id) => void handleDelete(id)} />
          ))}
        </div>
      )}
    </main>
  );
}
