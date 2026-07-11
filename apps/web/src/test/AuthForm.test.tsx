import { render, screen, fireEvent } from "@testing-library/react";
import { vi } from "vitest";
import AuthForm from "../components/AuthForm";

const signIn = vi.fn(() => Promise.resolve());
vi.mock("@convex-dev/auth/react", () => ({
  useAuthActions: () => ({ signIn, signOut: vi.fn() }),
}));

test("submits email/password with the signIn flow", async () => {
  render(<AuthForm />);
  fireEvent.change(screen.getByLabelText(/email/i), { target: { value: "a@b.com" } });
  fireEvent.change(screen.getByLabelText(/password/i), { target: { value: "pw123456" } });
  fireEvent.click(screen.getByRole("button", { name: /sign in/i }));
  expect(signIn).toHaveBeenCalledWith("password", {
    email: "a@b.com", password: "pw123456", flow: "signIn",
  });
});
