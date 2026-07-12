import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { vi } from "vitest";
import AuthForm from "@/features/auth/AuthForm";

const signIn = vi.fn(() => Promise.resolve());
vi.mock("@convex-dev/auth/react", () => ({
  useAuthActions: () => ({ signIn, signOut: vi.fn() }),
}));

test("submits email/password with the signIn flow", async () => {
  render(<AuthForm />);
  fireEvent.change(screen.getByLabelText(/email/i), { target: { value: "a@b.com" } });
  fireEvent.change(screen.getByLabelText(/password/i), { target: { value: "pw123456" } });
  fireEvent.click(screen.getByRole("button", { name: /sign in/i }));
  // await inside act via waitFor so the post-await setBusy(false) in AuthForm
  // doesn't resolve after the test body returns (which logged an act() warning).
  await waitFor(() => {
    expect(signIn).toHaveBeenCalledWith("password", {
      email: "a@b.com", password: "pw123456", flow: "signIn",
    });
  });
});
