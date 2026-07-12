import { useState } from "react";
import { Outlet } from "react-router-dom";
import { cn } from "@/lib/utils";
import Sidebar from "./Sidebar";
import { AppShellContext } from "./app-shell-context";

const HIDE_KEY = "privoice-nav-hidden";

function readHidden(): boolean {
  return typeof localStorage !== "undefined" && localStorage.getItem(HIDE_KEY) === "1";
}

export default function AppShell() {
  const [navOpen, setNavOpen] = useState(false);
  const [navHidden, setNavHidden] = useState(readHidden);

  function toggleDesktopNav() {
    setNavHidden((prev) => {
      const next = !prev;
      localStorage.setItem(HIDE_KEY, next ? "1" : "0");
      return next;
    });
  }

  return (
    <AppShellContext.Provider
      value={{
        openNav: () => setNavOpen(true),
        toggleDesktopNav,
        desktopNavHidden: navHidden,
      }}
    >
      <div className="flex h-screen overflow-hidden bg-background text-foreground">
        <Sidebar
          open={navOpen}
          desktopHidden={navHidden}
          onNavigate={() => setNavOpen(false)}
        />

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
