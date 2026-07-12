import { render, screen } from "@testing-library/react";
import { vi } from "vitest";
import DocumentsList from "@/features/documents/DocumentsList";

vi.mock("convex/react", () => ({
  useQuery: () => [
    { _id: "1", filename: "report.pdf", kind: "pdf", status: "ready", chunkCount: 12 },
    { _id: "2", filename: "data.xlsx", kind: "xlsx", status: "parsing", chunkCount: 0 },
  ],
  useMutation: () => vi.fn(),
}));

test("lists documents with status", () => {
  render(<DocumentsList />);
  expect(screen.getByText("report.pdf")).toBeInTheDocument();
  expect(screen.getByText("data.xlsx")).toBeInTheDocument();
  expect(screen.getByText(/ready/i)).toBeInTheDocument();
  expect(screen.getByText(/parsing/i)).toBeInTheDocument();
  expect(screen.getByLabelText(/upload/i)).toBeInTheDocument();
});
