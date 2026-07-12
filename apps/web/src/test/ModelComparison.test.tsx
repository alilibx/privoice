import { render, screen, fireEvent } from "@testing-library/react";
import ModelComparison from "@/features/settings/ModelComparison";

test("renders rows and calls onSelect", () => {
  const onSelect = vi.fn();
  render(
    <ModelComparison
      models={[
        { id: "openai/gpt-4o-mini", name: "GPT-4o mini", promptPrice: 0.15, completionPrice: 0.6, toolRating: "Good", ragRating: "Good" },
        { id: "anthropic/claude-sonnet-5", name: "Claude Sonnet 5", promptPrice: 2, completionPrice: 10, toolRating: "Best", ragRating: "Best" },
      ]}
      selectedId="openai/gpt-4o-mini"
      onSelect={onSelect}
    />,
  );
  expect(screen.getByText("GPT-4o mini")).toBeInTheDocument();
  expect(screen.getByText("Claude Sonnet 5")).toBeInTheDocument();
  fireEvent.click(screen.getByText("Claude Sonnet 5"));
  expect(onSelect).toHaveBeenCalledWith("anthropic/claude-sonnet-5");
});
