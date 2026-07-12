import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";

export type Meeting = {
  _id: string;
  title: string;
  createdAt: number;
};

export default function MeetingCard({
  meeting,
  onDelete,
}: {
  meeting: Meeting;
  onDelete: (id: string) => void;
}) {
  return (
    <Card>
      <CardContent className="flex items-center justify-between gap-3 p-4">
        <div className="min-w-0">
          <p className="truncate font-medium text-foreground">{meeting.title}</p>
          <p className="text-xs text-muted-foreground">
            {new Date(meeting.createdAt).toLocaleString()}
          </p>
        </div>
        <Button
          variant="ghost"
          size="icon"
          aria-label="Delete meeting"
          onClick={() => onDelete(meeting._id)}
        >
          <Trash2 className="size-4" />
        </Button>
      </CardContent>
    </Card>
  );
}
