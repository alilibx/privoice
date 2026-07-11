import { render, screen } from "@testing-library/react";
import { vi } from "vitest";
import App from "../App";

// App renders behind Convex's auth-state switch (AuthLoading/Unauthenticated/
// Authenticated), which needs a ConvexProviderWithAuth ancestor. This smoke
// test isn't about auth wiring, so stub both modules to force the
// unauthenticated path and assert the shell (AuthForm) renders.
vi.mock("convex/react", () => ({
  Authenticated: () => null,
  Unauthenticated: ({ children }: { children: React.ReactNode }) => <>{children}</>,
  AuthLoading: () => null,
}));
vi.mock("@convex-dev/auth/react", () => ({
  useAuthActions: () => ({ signIn: vi.fn(), signOut: vi.fn() }),
}));

test("renders the Privoice shell", () => {
  render(<App />);
  expect(screen.getByRole("heading", { name: "Privoice" })).toBeInTheDocument();
});
