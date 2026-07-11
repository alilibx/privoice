import { useState } from "react";
import { useAuthActions } from "@convex-dev/auth/react";

export default function AuthForm() {
  const { signIn } = useAuthActions();
  const [flow, setFlow] = useState<"signIn" | "signUp">("signIn");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true); setError(null);
    try {
      await signIn("password", { email, password, flow });
    } catch (err) {
      setError(flow === "signIn" ? "Could not sign in." : "Could not sign up.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="min-h-screen grid place-items-center p-6">
      <form onSubmit={submit}
        className="w-full max-w-sm rounded-xl border border-outline bg-surface p-8 space-y-4">
        <h1 className="text-2xl font-bold text-primary">Privoice</h1>
        <label className="block text-sm">Email
          <input aria-label="Email" type="email" required value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="mt-1 w-full rounded-lg border border-outline px-3 py-2" />
        </label>
        <label className="block text-sm">Password
          <input aria-label="Password" type="password" required value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="mt-1 w-full rounded-lg border border-outline px-3 py-2" />
        </label>
        {error && <p className="text-sm text-red-600">{error}</p>}
        <button type="submit" disabled={busy}
          className="w-full rounded-lg bg-primary py-2 font-semibold text-white disabled:opacity-60">
          {flow === "signIn" ? "Sign in" : "Sign up"}
        </button>
        <button type="button" onClick={() => setFlow(flow === "signIn" ? "signUp" : "signIn")}
          className="w-full text-sm text-primary">
          {flow === "signIn" ? "Need an account? Sign up" : "Have an account? Sign in"}
        </button>
      </form>
    </main>
  );
}
