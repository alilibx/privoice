import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { vi } from "vitest";
import { getFunctionName } from "convex/server";
import MeetingsList from "@/features/meetings/MeetingsList";
import { api } from "../../convex/_generated/api";

const create = vi.fn(() => Promise.resolve());
const remove = vi.fn(() => Promise.resolve());
vi.mock("convex/react", () => ({
  useQuery: () => [{ _id: "1", title: "Existing", createdAt: 0, status: "note" }],
  useMutation: (fn: unknown) =>
    getFunctionName(fn as Parameters<typeof getFunctionName>[0]) ===
    getFunctionName(api.meetings.remove)
      ? remove
      : create,
}));

test("renders heading, new-meeting trigger, and meeting list", () => {
  render(<MeetingsList />);
  expect(screen.getByRole("heading", { name: /meetings/i })).toBeInTheDocument();
  expect(screen.getByText("Existing")).toBeInTheDocument();
  expect(screen.getByRole("button", { name: /new meeting/i })).toBeInTheDocument();
  expect(screen.getByRole("button", { name: /delete/i })).toBeInTheDocument();
});

test("creates a new meeting via the dialog", async () => {
  render(<MeetingsList />);
  fireEvent.click(screen.getByRole("button", { name: /new meeting/i }));
  fireEvent.change(screen.getByLabelText(/title/i), { target: { value: "Standup" } });
  fireEvent.click(screen.getByRole("button", { name: /^create$/i }));
  await waitFor(() => {
    expect(create).toHaveBeenCalledWith({ title: "Standup", notes: undefined });
  });
});

test("deletes a meeting", async () => {
  render(<MeetingsList />);
  fireEvent.click(screen.getByRole("button", { name: /delete/i }));
  await waitFor(() => {
    expect(remove).toHaveBeenCalledWith({ id: "1" });
  });
});
