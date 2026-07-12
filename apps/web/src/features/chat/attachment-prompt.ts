// When a message carries freshly-uploaded attachments, we append a short
// grounding instruction to the prompt so the assistant answers about THOSE
// documents (a bare "what is this" otherwise gives RAG nothing to latch onto
// and it drifts to older documents). The instruction is stripped from the
// visible user bubble via `displayText` — the chip already shows the file.

const MARKER = "\n\n———\nAttached to this message:";

export function withAttachmentContext(text: string, filenames: string[]): string {
  if (filenames.length === 0) return text;
  const list = filenames.map((f) => `"${f}"`).join(", ");
  return `${text}${MARKER} ${list}. Answer using these just-uploaded document(s); when the question refers to "this" or the attachment, ground your response in them specifically rather than older documents.`;
}

/** The user-visible text — everything before the appended attachment marker. */
export function displayText(raw: string): string {
  const i = raw.indexOf(MARKER);
  return i === -1 ? raw : raw.slice(0, i).trimEnd();
}
