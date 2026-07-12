import { useState } from "react";
import { Outlet } from "react-router-dom";
import { cn } from "@/lib/utils";
import Sidebar from "./Sidebar";
import { AppShellContext } from "./app-shell-context";

export default function AppShell() {
  const [navOpen, setNavOpen] = useState(false);

  return (
    <AppShellContext.Provider value={{ openNav: () => setNavOpen(true) }}>
      <div className="flex h-screen overflow-hidden bg-background text-foreground">
        <Sidebar open={navOpen} onNavigate={() => setNavOpen(false)} />

        {/* Scrim behind the mobile nav drawer. */}
        <div
          aria-hidden
          onClick={() => setNavOpen(false)}
          className={cn(
            "fixed inset-0 z-30 bg-black/40 transition-opacity duration-300 lg:hidden",
            navOpen ? "opacity-100" : "pointer-events-none opacity-0",
          )}
        />

        <main className="flex min-w-0 flex-1 flex-col overflow-hidden">
          <Outlet />
        </main>
      </div>
    </AppShellContext.Provider>
  );
}
