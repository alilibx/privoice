import { AudioLines } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * The Privoice glyph — a gradient teal tile with a soundwave mark (voice).
 * Reused for the sidebar wordmark and the assistant avatar so the brand is
 * one consistent object across the app.
 */
export default function BrandMark({ className }: { className?: string }) {
  return (
    <span
      className={cn(
        "brandmark grid place-items-center rounded-[10px] text-primary-foreground shadow-sm",
        className,
      )}
    >
      <AudioLines className="size-1/2" strokeWidth={2.2} />
    </span>
  );
}
