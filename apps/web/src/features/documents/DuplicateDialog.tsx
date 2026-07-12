import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";

export default function DuplicateDialog({
  open,
  filename,
  onOpenChange,
  onUseExisting,
  onUploadAnyway,
}: {
  open: boolean;
  filename: string;
  onOpenChange: (open: boolean) => void;
  onUseExisting: () => void;
  onUploadAnyway: () => void;
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>You already have this file</DialogTitle>
          <DialogDescription>
            <span className="font-medium text-foreground">{filename}</span> is
            already in your documents and hasn&apos;t changed. Upload another
            copy?
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" onClick={onUploadAnyway}>
            Upload anyway
          </Button>
          <Button onClick={onUseExisting}>Use existing</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
