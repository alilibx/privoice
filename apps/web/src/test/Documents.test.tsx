import { render, screen } from "@testing-library/react";
import { vi } from "vitest";
import Documents from "../components/Documents";

vi.mock("convex/react", () => ({
  useQuery: () => [
    { _id: "1", filename: "report.pdf", kind: "pdf", status: "ready", chunkCount: 12 },
    { _id: "2", filename: "data.xlsx", kind: "xlsx", status: "parsing", chunkCount: 0 },
  ],
  useMutation: () => vi.fn(),
}));

test("lists documents with status", () => {
  render(<Documents />);
  expect(screen.getByText("report.pdf")).toBeInTheDocument();
  expect(screen.getByText("data.xlsx")).toBeInTheDocument();
  expect(screen.getByText(/parsing/i)).toBeInTheDocument();
});
