import { render, screen } from "@testing-library/react";
import App from "../App";

test("renders the Privoice shell", () => {
  render(<App />);
  expect(screen.getByRole("heading", { name: "Privoice" })).toBeInTheDocument();
});
