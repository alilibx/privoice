import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { vi } from "vitest";
import Dashboard from "../components/Dashboard";

const create = vi.fn(() => Promise.resolve());
vi.mock("convex/react", () => ({
  useQuery: () => [{ _id: "1", title: "Existing", createdAt: 0, status: "note" }],
  useMutation: () => create,
}));
vi.mock("@convex-dev/auth/react", () => ({ useAuthActions: () => ({ signOut: vi.fn() }) }));

test("lists meetings and creates a new one", async () => {
  render(<Dashboard />);
  expect(screen.getByText("Existing")).toBeInTheDocument();
  fireEvent.change(screen.getByLabelText(/new meeting title/i), { target: { value: "Standup" } });
  fireEvent.click(screen.getByRole("button", { name: /add/i }));
  // await the mutation's promise (and its subsequent setTitle) inside act via waitFor,
  // so the assertion doesn't race the unresolved microtask (which would otherwise
  // resolve after the test body returns and log an act() warning).
  await waitFor(() => {
    expect(create).toHaveBeenCalledWith({ title: "Standup", notes: undefined });
  });
});
