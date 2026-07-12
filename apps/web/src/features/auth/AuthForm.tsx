import { useState } from "react";
import { useAuthActions } from "@convex-dev/auth/react";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import BrandMark from "@/components/layout/BrandMark";

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
    <main className="chat-canvas grid min-h-screen place-items-center p-6">
      <div className="w-full max-w-sm">
        <div className="mb-6 flex flex-col items-center text-center">
          <BrandMark className="h-12 w-12" />
          <h1 className="mt-4 font-display text-3xl font-semibold tracking-tight">
            Privoice
          </h1>
          <p className="mt-1.5 text-sm text-muted-foreground">
            {flow === "signIn"
              ? "Sign in to your private workspace"
              : "Create your private workspace"}
          </p>
        </div>
        <Card className="w-full">
        <CardContent className="pt-6">
          <form onSubmit={submit} className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor="auth-email">Email</Label>
              <Input
                id="auth-email"
                aria-label="Email"
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="auth-password">Password</Label>
              <Input
                id="auth-password"
                aria-label="Password"
                type="password"
                required
                minLength={MIN_PASSWORD}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
              <p className="text-xs text-muted-foreground">
                At least {MIN_PASSWORD} characters.
              </p>
            </div>
            {error && <p className="text-sm text-destructive">{error}</p>}
            <Button type="submit" disabled={busy} className="w-full">
              {busy ? "…" : flow === "signIn" ? "Sign in" : "Sign up"}
            </Button>
            <Button
              type="button"
              variant="link"
              className="w-full"
              onClick={() => {
                setFlow(flow === "signIn" ? "signUp" : "signIn");
                setError(null);
              }}
            >
              {flow === "signIn"
                ? "Need an account? Sign up"
                : "Have an account? Sign in"}
            </Button>
          </form>
        </CardContent>
        </Card>
      </div>
    </main>
  );
}
