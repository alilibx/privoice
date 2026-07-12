import { render, screen } from "@testing-library/react";
import AttachmentCard from "@/features/chat/AttachmentCard";

test("shows filename, size and status by kind", () => {
  render(<AttachmentCard attachment={{ docId: "d1", filename: "Q3.pdf", kind: "pdf", sizeBytes: 2048 }} status="parsing" />);
  expect(screen.getByText("Q3.pdf")).toBeInTheDocument();
  expect(screen.getByText(/2(\.0)? KB/)).toBeInTheDocument();
  // "parsing" status reads as "Loading…" to the user (part of the upload).
  expect(screen.getByText(/loading/i)).toBeInTheDocument();
});
