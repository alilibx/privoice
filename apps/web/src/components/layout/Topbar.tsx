import { useLocation } from "react-router-dom";
import ThemeToggle from "./ThemeToggle";
import UserMenu from "./UserMenu";

const TITLES: Record<string, string> = {
  "/chat": "Chat",
  "/meetings": "Meetings",
  "/documents": "Documents",
  "/settings": "Settings",
};

export default function Topbar({ title }: { title?: string }) {
  const location = useLocation();
  const derived = TITLES[location.pathname] ?? "Privoice";

  return (
    <header className="flex h-14 items-center justify-between border-b border-border bg-background px-4">
      <h1 className="text-lg font-semibold">{title ?? derived}</h1>
      <div className="flex items-center gap-2">
        <ThemeToggle />
        <UserMenu />
      </div>
    </header>
  );
}
