import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { vi, expect, test } from "vitest";
import { getFunctionName } from "convex/server";
import DocumentsList from "@/features/documents/DocumentsList";
import { api } from "../../convex/_generated/api";

vi.mock("@/features/documents/content-hash", () => ({
  hashFile: vi.fn(async () => "hash-abc"),
  sha256Hex: vi.fn(async () => "hash-abc"),
}));

const createMock = vi.fn(async () => "newdoc");

vi.mock("convex/react", () => ({
  useQuery: (q: Parameters<typeof getFunctionName>[0]) => {
    if (getFunctionName(q) === getFunctionName(api.documents.list))
      return [
        {
          _id: "1",
          filename: "report.pdf",
          kind: "pdf",
          status: "ready",
          chunkCount: 12,
          sizeBytes: 10,
          contentHash: "hash-abc",
        },
        { _id: "2", filename: "data.xlsx", kind: "xlsx", status: "parsing", chunkCount: 0, sizeBytes: 5 },
      ];
    return [];
  },
  useMutation: (m: Parameters<typeof getFunctionName>[0]) => {
    if (getFunctionName(m) === getFunctionName(api.documents.create)) return createMock;
    if (getFunctionName(m) === getFunctionName(api.documents.generateUploadUrl))
      return vi.fn(async () => "https://upload");
    return vi.fn();
  },
}));

test("lists documents with status", () => {
  render(<DocumentsList />);
  expect(screen.getByText("report.pdf")).toBeInTheDocument();
  expect(screen.getByText("data.xlsx")).toBeInTheDocument();
  expect(screen.getByText(/ready/i)).toBeInTheDocument();
  expect(screen.getByText(/parsing/i)).toBeInTheDocument();
  expect(screen.getByLabelText(/upload/i)).toBeInTheDocument();
});

test("same name + same hash opens the duplicate dialog; Use existing skips create", async () => {
  createMock.mockClear();
  render(<DocumentsList />);

  const input = document.querySelector('input[type="file"]') as HTMLInputElement;
  const file = new File([new Uint8Array([1])], "report.pdf", { type: "application/pdf" });
  fireEvent.change(input, { target: { files: [file] } });

  await screen.findByText("You already have this file");
  fireEvent.click(screen.getByRole("button", { name: /use existing/i }));
  await waitFor(() =>
    expect(screen.queryByText("You already have this file")).not.toBeInTheDocument(),
  );
  expect(createMock).not.toHaveBeenCalled();
});
