import { useState } from "react";
import { useAuthActions } from "@convex-dev/auth/react";

// Convex Auth's Password provider requires at least 8 characters.
const MIN_PASSWORD = 8;

export default function AuthForm() {
  const { signIn } = useAuthActions();
  const [flow, setFlow] = useState<"signIn" | "signUp">("signIn");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (password.length < MIN_PASSWORD) {
      setError(`Password must be at least ${MIN_PASSWORD} characters.`);
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await signIn("password", { email, password, flow });
    } catch (err) {
      // Surface the real reason (e.g. wrong credentials, account exists /
      // doesn't exist, weak password) instead of a blanket message.
      const detail = err instanceof Error && err.message ? err.message : "";
      const base =
        flow === "signIn"
          ? "Could not sign in — check your email and password, or sign up first."
          : "Could not sign up.";
      setError(detail ? `${base} (${detail})` : base);
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="min-h-screen grid place-items-center p-6">
      <form
        onSubmit={submit}
        className="w-full max-w-sm rounded-xl border border-outline bg-surface p-8 space-y-4"
      >
        <h1 className="text-2xl font-bold text-primary">Privoice</h1>
        <label className="block text-sm font-medium text-on-surface">
          Email
          <input
            aria-label="Email"
            type="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="mt-1 w-full rounded-lg border border-outline bg-surface px-3 py-2 text-on-surface placeholder:text-on-surface-variant focus:outline-none focus:ring-2 focus:ring-primary"
          />
        </label>
        <label className="block text-sm font-medium text-on-surface">
          Password
          <input
            aria-label="Password"
            type="password"
            required
            minLength={MIN_PASSWORD}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="mt-1 w-full rounded-lg border border-outline bg-surface px-3 py-2 text-on-surface placeholder:text-on-surface-variant focus:outline-none focus:ring-2 focus:ring-primary"
          />
          <span className="mt-1 block text-xs text-on-surface-variant">
            At least {MIN_PASSWORD} characters.
          </span>
        </label>
        {error && <p className="text-sm text-red-600">{error}</p>}
        <button
          type="submit"
          disabled={busy}
          className="w-full rounded-lg bg-primary py-2 font-semibold text-white disabled:opacity-60"
        >
          {busy ? "…" : flow === "signIn" ? "Sign in" : "Sign up"}
        </button>
        <button
          type="button"
          onClick={() => {
            setFlow(flow === "signIn" ? "signUp" : "signIn");
            setError(null);
          }}
          className="w-full text-sm text-primary"
        >
          {flow === "signIn"
            ? "Need an account? Sign up"
            : "Have an account? Sign in"}
        </button>
      </form>
    </main>
  );
}
