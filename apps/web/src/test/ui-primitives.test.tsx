import { render, screen } from "@testing-library/react";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import { Skeleton } from "@/components/ui/skeleton";

test("core primitives render", () => {
  render(<><Badge variant="success">Ready</Badge><Textarea aria-label="msg" /><Skeleton className="h-4 w-4" /></>);
  expect(screen.getByText("Ready")).toBeInTheDocument();
  expect(screen.getByLabelText("msg")).toBeInTheDocument();
});
