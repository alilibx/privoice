import { render, screen } from "@testing-library/react";
import Markdown from "@/features/chat/Markdown";

test("renders GFM markdown as real elements, not raw text", () => {
  const { container } = render(
    <Markdown>{"## Overview\n\nRevenue grew **12%** this quarter.\n\n- First point\n- Second point"}</Markdown>,
  );

  // Bold becomes <strong>, not literal asterisks.
  const strong = screen.getByText("12%");
  expect(strong.tagName).toBe("STRONG");
  expect(container.textContent).not.toContain("**");

  // Heading becomes a real heading element.
  expect(screen.getByRole("heading", { name: /overview/i })).toBeInTheDocument();

  // List items render as <li>.
  expect(screen.getAllByRole("listitem")).toHaveLength(2);
  expect(screen.getByText("First point")).toBeInTheDocument();
});
