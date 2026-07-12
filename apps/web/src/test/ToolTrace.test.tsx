import { render, screen } from "@testing-library/react";
import ToolTrace from "@/features/chat/ToolTrace";

test("renders a labeled step per tool part and nothing when none", () => {
  const { rerender } = render(
    <ToolTrace parts={[
      { type: "tool-searchKnowledge", state: "output-available", input: { query: "Q3 revenue" } },
      { type: "text" },
    ]} />,
  );
  expect(screen.getByText(/searched your knowledge/i)).toBeInTheDocument();
  expect(screen.getByText(/Q3 revenue/)).toBeInTheDocument();

  rerender(<ToolTrace parts={[{ type: "text" }]} />);
  expect(screen.queryByText(/searched your/i)).not.toBeInTheDocument();
});
