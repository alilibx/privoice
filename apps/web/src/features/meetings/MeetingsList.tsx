import { useQuery, useMutation } from "convex/react";
import { toast } from "sonner";
import { api } from "../../../convex/_generated/api";
import type { Id } from "../../../convex/_generated/dataModel";
import PageHeader from "@/components/layout/PageHeader";
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
    <div className="flex h-full flex-col">
      <PageHeader title="Meetings" actions={<NewMeetingDialog onCreate={handleCreate} />} />
      <div className="flex-1 overflow-y-auto">
        <div className="mx-auto max-w-3xl p-4 sm:p-6">
          {meetings.length === 0 ? (
            <p className="mt-16 text-center text-muted-foreground">
              No meetings yet
            </p>
          ) : (
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              {meetings.map((m) => (
                <MeetingCard
                  key={m._id}
                  meeting={m}
                  onDelete={(id) => void handleDelete(id)}
                />
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
