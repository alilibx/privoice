import { NavLink } from "react-router-dom";
import {
  MessageSquare,
  CalendarDays,
  FileText,
  Settings,
  PanelLeftClose,
} from "lucide-react";
import { cn } from "@/lib/utils";
import BrandMark from "./BrandMark";
import UserMenu from "./UserMenu";
import { useAppShell } from "./app-shell-context";

const NAV_ITEMS = [
  { to: "/chat", label: "Chat", icon: MessageSquare },
  { to: "/meetings", label: "Meetings", icon: CalendarDays },
  { to: "/documents", label: "Documents", icon: FileText },
  { to: "/settings", label: "Settings", icon: Settings },
];

/**
 * The app's primary navigation. One element that is a static column on `lg+`
 * and an off-canvas drawer (translated by `open`) on smaller screens.
 * `onNavigate` lets the mobile drawer close itself after a route change.
 */
export default function Sidebar({
  open,
  desktopHidden = false,
  onNavigate,
}: {
  open: boolean;
  desktopHidden?: boolean;
  onNavigate?: () => void;
}) {
  const { toggleDesktopNav } = useAppShell();
  return (
    <aside
      className={cn(
        "fixed inset-y-0 left-0 z-40 flex w-[264px] flex-col border-r bg-sidebar text-sidebar-foreground transition-transform duration-300 ease-out",
        open ? "translate-x-0 shadow-2xl" : "-translate-x-full",
        // On lg+: shown as a static column, or fully hidden when collapsed.
        desktopHidden
          ? "lg:hidden"
          : "lg:static lg:z-auto lg:w-[248px] lg:translate-x-0 lg:shadow-none",
      )}
    >
      <div className="flex h-16 items-center gap-2.5 px-5">
        <BrandMark className="h-8 w-8" />
        <span className="font-display text-[22px] font-semibold tracking-tight">
          Privoice
        </span>
        <button
          type="button"
          aria-label="Hide sidebar"
          title="Hide sidebar"
          onClick={toggleDesktopNav}
          className="ml-auto hidden h-8 w-8 place-items-center rounded-lg text-muted-foreground hover:bg-accent hover:text-foreground lg:grid"
        >
          <PanelLeftClose className="h-[18px] w-[18px]" />
        </button>
      </div>

      <nav className="flex-1 space-y-0.5 px-3 pt-2">
        {NAV_ITEMS.map(({ to, label, icon: Icon }) => (
          <NavLink
            key={to}
            to={to}
            onClick={onNavigate}
            className={({ isActive }) =>
              cn(
                "flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
                isActive
                  ? "bg-primary text-primary-foreground shadow-sm"
                  : "text-muted-foreground hover:bg-accent hover:text-accent-foreground",
              )
            }
          >
            <Icon className="h-[18px] w-[18px] shrink-0" />
            {label}
          </NavLink>
        ))}
      </nav>

      <div className="border-t p-3">
        <UserMenu />
      </div>
    </aside>
  );
}
