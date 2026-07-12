import { render, screen } from "@testing-library/react";
import Sources, { parseSources, type SourceRef } from "@/features/chat/Sources";

const SAMPLE: SourceRef[] = [
  { n: 1, source: "document", sourceId: "doc1", title: "Q3 Revenue Report", locator: "document" },
  { n: 2, source: "meeting", sourceId: "mtg1", title: "Planning sync", locator: "meeting" },
];

describe("parseSources", () => {
  test("parses a valid <<<SOURCES>>> block", () => {
    const toolOutput = `Revenue grew 12%.\n\n<<<SOURCES>>>\n${JSON.stringify(SAMPLE)}`;
    expect(parseSources(toolOutput)).toEqual(SAMPLE);
  });

  test("returns [] when the marker is absent", () => {
    expect(parseSources("Just a plain answer with no sources.")).toEqual([]);
  });

  test("returns [] when the JSON after the marker is malformed", () => {
    expect(parseSources("Answer text\n\n<<<SOURCES>>>\nnot json{{{")).toEqual([]);
  });

  test("filters out malformed entries but keeps valid ones", () => {
    const mixed = [
      { n: 1, source: "document", sourceId: "doc1", title: "Valid", locator: "document" },
      { n: "two", title: "Bad n" },
      { title: "Missing n" },
      { n: 3 },
    ];
    const toolOutput = `Answer\n\n<<<SOURCES>>>\n${JSON.stringify(mixed)}`;
    expect(parseSources(toolOutput)).toEqual([
      { n: 1, source: "document", sourceId: "doc1", title: "Valid", locator: "document" },
    ]);
  });

  test("returns [] when the parsed value is not an array", () => {
    const toolOutput = `Answer\n\n<<<SOURCES>>>\n${JSON.stringify({ n: 1, title: "not an array" })}`;
    expect(parseSources(toolOutput)).toEqual([]);
  });
});

describe("Sources", () => {
  test("renders nothing when empty", () => {
    const { container } = render(<Sources sources={[]} />);
    expect(container).toBeEmptyDOMElement();
  });

  test("renders a heading, numbers, titles, and locators", () => {
    render(<Sources sources={SAMPLE} />);
    expect(screen.getByText("Sources")).toBeInTheDocument();
    expect(screen.getByText(/Q3 Revenue Report/)).toBeInTheDocument();
    expect(screen.getByText(/Planning sync/)).toBeInTheDocument();
    expect(screen.getByText("[1]")).toBeInTheDocument();
    expect(screen.getByText("[2]")).toBeInTheDocument();
  });

  test("gives each row an id for anchor scrolling", () => {
    const { container } = render(<Sources sources={SAMPLE} />);
    expect(container.querySelector("#source-1")).toBeInTheDocument();
    expect(container.querySelector("#source-2")).toBeInTheDocument();
  });
});
