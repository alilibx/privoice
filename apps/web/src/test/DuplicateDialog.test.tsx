import { render, screen, fireEvent } from "@testing-library/react";
import { vi, expect, test } from "vitest";
import DuplicateDialog from "@/features/documents/DuplicateDialog";

test("shows the filename and fires the right callbacks", () => {
  const onUseExisting = vi.fn();
  const onUploadAnyway = vi.fn();
  render(
    <DuplicateDialog
      open
      filename="report.pdf"
      onOpenChange={() => {}}
      onUseExisting={onUseExisting}
      onUploadAnyway={onUploadAnyway}
    />,
  );
  expect(screen.getByText("report.pdf")).toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: /use existing/i }));
  expect(onUseExisting).toHaveBeenCalledTimes(1);
  fireEvent.click(screen.getByRole("button", { name: /upload anyway/i }));
  expect(onUploadAnyway).toHaveBeenCalledTimes(1);
});
