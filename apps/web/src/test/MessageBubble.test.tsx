import { render, screen } from "@testing-library/react";
import { vi } from "vitest";
import MessageBubble from "@/features/chat/MessageBubble";

vi.mock("@convex-dev/agent/react", () => ({
  useSmoothText: (text: string) => [text, { cursor: text.length, isStreaming: false }],
}));

// Minor #2 regression: each tool-searchKnowledge call's SourceRef.n restarts
// at 1 (see convex/retrieval/pack.ts's packContext), so concatenating
// sources from multiple tool-searchKnowledge parts on one message can
// produce duplicate `n` values -> duplicate id="source-N" DOM nodes,
// duplicate React keys, and an ambiguous rendered Sources list. MessageBubble
// must renumber sequentially across the merged list.
function sourcesBlock(entries: Array<{ n: number; sourceId: string; title: string }>) {
  const sources = entries.map((e) => ({
    n: e.n,
    source: "document",
    sourceId: e.sourceId,
    title: e.title,
    locator: "document",
  }));
  return `some pack text\n\n<<<SOURCES>>>\n${JSON.stringify(sources)}`;
}

test("renumbers sources sequentially across multiple tool-searchKnowledge parts (no duplicate n)", () => {
  const message = {
    key: "m1",
    role: "assistant",
    text: "Here is the answer.",
    status: "success",
    parts: [
      {
        type: "tool-searchKnowledge",
        state: "output-available",
        output: sourcesBlock([{ n: 1, sourceId: "doc-a", title: "Doc A" }]),
      },
      {
        type: "tool-searchKnowledge",
        state: "output-available",
        // Second call's SourceRef.n ALSO restarts at 1, per pack.ts.
        output: sourcesBlock([{ n: 1, sourceId: "doc-b", title: "Doc B" }]),
      },
      { type: "text", text: "Here is the answer." },
    ],
  };

  const { container } = render(<MessageBubble message={message} />);

  // Both sources render, each with a UNIQUE anchor id — not two "source-1"s.
  expect(container.querySelector("#source-1")).toBeInTheDocument();
  expect(container.querySelector("#source-2")).toBeInTheDocument();
  expect(screen.getByText("[1]")).toBeInTheDocument();
  expect(screen.getByText("[2]")).toBeInTheDocument();
  expect(screen.getByText(/Doc A/)).toBeInTheDocument();
  expect(screen.getByText(/Doc B/)).toBeInTheDocument();
});

test("a single searchKnowledge call is unaffected (n already 1..N)", () => {
  const message = {
    key: "m1",
    role: "assistant",
    text: "Here is the answer.",
    status: "success",
    parts: [
      {
        type: "tool-searchKnowledge",
        state: "output-available",
        output: sourcesBlock([
          { n: 1, sourceId: "doc-a", title: "Doc A" },
          { n: 2, sourceId: "doc-b", title: "Doc B" },
        ]),
      },
      { type: "text", text: "Here is the answer." },
    ],
  };

  const { container } = render(<MessageBubble message={message} />);
  expect(container.querySelector("#source-1")).toBeInTheDocument();
  expect(container.querySelector("#source-2")).toBeInTheDocument();
});
