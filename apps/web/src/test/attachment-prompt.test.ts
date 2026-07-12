import { withAttachmentContext, displayText } from "@/features/chat/attachment-prompt";

test("no attachments leaves the text untouched", () => {
  expect(withAttachmentContext("what is this", [])).toBe("what is this");
  expect(displayText("what is this")).toBe("what is this");
});

test("attachments append a grounding note that names the files", () => {
  const prompt = withAttachmentContext("what is this", ["Kakeibo.pdf", "Q3.xlsx"]);
  expect(prompt).toContain("Kakeibo.pdf");
  expect(prompt).toContain("Q3.xlsx");
  // The model is told to ground on the just-uploaded docs.
  expect(prompt.toLowerCase()).toContain("just-uploaded");
});

test("displayText strips the appended note, leaving only the user's words", () => {
  const prompt = withAttachmentContext("what is this", ["Kakeibo.pdf"]);
  expect(displayText(prompt)).toBe("what is this");
});
