import { Authenticated, Unauthenticated, AuthLoading } from "convex/react";
import { useAuthActions } from "@convex-dev/auth/react";
import AuthForm from "./components/AuthForm";

export default function App() {
  const { signOut } = useAuthActions();
  return (
    <>
      <AuthLoading>
        <main className="min-h-screen grid place-items-center">Loading…</main>
      </AuthLoading>
      <Unauthenticated>
        <AuthForm />
      </Unauthenticated>
      <Authenticated>
        {/* Dashboard replaces this in Task 4 */}
        <main className="min-h-screen p-6">
          <button onClick={() => signOut()} className="text-primary">Sign out</button>
          <p className="mt-4 text-on-surface-variant">Signed in.</p>
        </main>
      </Authenticated>
    </>
  );
}
