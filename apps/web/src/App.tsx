import { useState } from "react";
import { Authenticated, Unauthenticated, AuthLoading } from "convex/react";
import { useAuthActions } from "@convex-dev/auth/react";
import AuthForm from "./components/AuthForm";
import Dashboard from "./components/Dashboard";
import Documents from "./components/Documents";

function AuthenticatedShell() {
  const [view, setView] = useState<"meetings" | "documents">("meetings");
  const { signOut } = useAuthActions();

  return (
    <>
      <nav className="mx-auto flex max-w-2xl items-center gap-2 px-6 pt-6">
        <button
          onClick={() => setView("meetings")}
          aria-current={view === "meetings" || undefined}
          className={
            view === "meetings"
              ? "rounded-lg bg-primary px-4 py-2 font-semibold text-white"
              : "rounded-lg px-4 py-2 font-semibold text-on-surface-variant hover:text-primary"
          }
        >
          Meetings
        </button>
        <button
          onClick={() => setView("documents")}
          aria-current={view === "documents" || undefined}
          className={
            view === "documents"
              ? "rounded-lg bg-primary px-4 py-2 font-semibold text-white"
              : "rounded-lg px-4 py-2 font-semibold text-on-surface-variant hover:text-primary"
          }
        >
          Documents
        </button>
        <button
          onClick={() => signOut()}
          className="ml-auto rounded-lg px-4 py-2 text-sm font-semibold text-on-surface-variant hover:text-primary"
        >
          Sign out
        </button>
      </nav>
      {view === "meetings" ? <Dashboard /> : <Documents />}
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
