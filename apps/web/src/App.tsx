import { useState } from "react";
import { Authenticated, Unauthenticated, AuthLoading } from "convex/react";
import { useAuthActions } from "@convex-dev/auth/react";
import AuthForm from "./components/AuthForm";
import Dashboard from "./components/Dashboard";
import Documents from "./components/Documents";
import Chat from "./components/Chat";

type View = "chat" | "meetings" | "documents";

function NavButton({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      aria-current={active || undefined}
      className={
        active
          ? "rounded-lg bg-primary px-4 py-2 font-semibold text-white"
          : "rounded-lg px-4 py-2 font-semibold text-on-surface-variant hover:text-primary"
      }
    >
      {children}
    </button>
  );
}

function AuthenticatedShell() {
  const [view, setView] = useState<View>("chat");
  const { signOut } = useAuthActions();

  return (
    <>
      <nav className="mx-auto flex max-w-4xl items-center gap-2 px-6 pt-6">
        <NavButton active={view === "chat"} onClick={() => setView("chat")}>
          Chat
        </NavButton>
        <NavButton active={view === "meetings"} onClick={() => setView("meetings")}>
          Meetings
        </NavButton>
        <NavButton active={view === "documents"} onClick={() => setView("documents")}>
          Documents
        </NavButton>
        <button
          onClick={() => signOut()}
          className="ml-auto rounded-lg px-4 py-2 text-sm font-semibold text-on-surface-variant hover:text-primary"
        >
          Sign out
        </button>
      </nav>
      {view === "chat" && <Chat />}
      {view === "meetings" && <Dashboard />}
      {view === "documents" && <Documents />}
    </>
  );
}

export default function App() {
  return (
    <>
      <AuthLoading>
        <main className="min-h-screen grid place-items-center">Loading…</main>
      </AuthLoading>
      <Unauthenticated>
        <AuthForm />
      </Unauthenticated>
      <Authenticated>
        <AuthenticatedShell />
      </Authenticated>
    </>
  );
}
