import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { vi } from "vitest";
import { ThemeProvider } from "@/lib/theme-provider";
import AppShell from "@/components/layout/AppShell";

vi.mock("convex/react", () => ({
  useQuery: () => undefined,
}));
vi.mock("@convex-dev/auth/react", () => ({
  useAuthActions: () => ({ signOut: vi.fn() }),
}));

test("renders the sidebar nav with all four routes", () => {
  render(
    <MemoryRouter>
      <ThemeProvider defaultTheme="light">
        <AppShell />
      </ThemeProvider>
    </MemoryRouter>,
  );

  expect(screen.getByText("Chat")).toBeInTheDocument();
  expect(screen.getByText("Meetings")).toBeInTheDocument();
  expect(screen.getByText("Documents")).toBeInTheDocument();
  expect(screen.getByText("Settings")).toBeInTheDocument();
});
