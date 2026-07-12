import { Menu } from "lucide-react";
import { useAppShell } from "./app-shell-context";

/**
 * Shared header for the non-chat pages (Meetings / Documents / Settings).
 * Carries the mobile hamburger that opens the nav drawer, the page title in
 * the display face, and an optional right-aligned actions slot.
 */
export default function PageHeader({
  title,
  actions,
}: {
  title: string;
  actions?: React.ReactNode;
}) {
  const { openNav } = useAppShell();
  return (
    <header className="sticky top-0 z-20 flex h-16 shrink-0 items-center gap-2 border-b bg-background/70 px-4 backdrop-blur-xl sm:px-6">
      <button
        type="button"
        aria-label="Open menu"
        onClick={openNav}
        className="-ml-1 grid h-10 w-10 place-items-center rounded-lg text-muted-foreground hover:bg-accent hover:text-foreground lg:hidden"
      >
        <Menu className="h-5 w-5" />
      </button>
      <h1 className="min-w-0 flex-1 truncate font-display text-xl font-semibold tracking-tight">
        {title}
      </h1>
      {actions}
    </header>
  );
}
