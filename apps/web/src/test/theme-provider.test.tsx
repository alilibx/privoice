import { render, screen, fireEvent } from "@testing-library/react";
import { ThemeProvider, useTheme } from "@/lib/theme-provider";

function Probe() {
  const { resolvedTheme, setTheme } = useTheme();
  return (
    <div>
      <span data-testid="resolved">{resolvedTheme}</span>
      <button onClick={() => setTheme("dark")}>go dark</button>
    </div>
  );
}

test("defaults to light and toggles dark class", () => {
  render(<ThemeProvider defaultTheme="light"><Probe /></ThemeProvider>);
  expect(screen.getByTestId("resolved")).toHaveTextContent("light");
  fireEvent.click(screen.getByText("go dark"));
  expect(document.documentElement.classList.contains("dark")).toBe(true);
  expect(screen.getByTestId("resolved")).toHaveTextContent("dark");
});
