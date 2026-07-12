import { render, screen, fireEvent } from "@testing-library/react";
import { vi, expect, test, beforeAll } from "vitest";
import ThreadList, { type ThreadRow } from "@/features/chat/ThreadList";

// Radix menus probe pointer-capture + scroll APIs jsdom doesn't implement.
beforeAll(() => {
  Element.prototype.hasPointerCapture = vi.fn(() => false);
  Element.prototype.scrollIntoView = vi.fn();
});

const threads: ThreadRow[] = [
  { _id: "1", threadId: "t1", title: "Q3 planning", createdAt: 1 },
  { _id: "2", threadId: "t2", title: "Roadmap", createdAt: 2 },
];

function setup(onDelete = vi.fn()) {
  render(
    <ThreadList
      threads={threads}
      activeThreadId="t1"
      onSelect={vi.fn()}
      onNewChat={vi.fn()}
      open
      onClose={vi.fn()}
      onDelete={onDelete}
    />,
  );
  return onDelete;
}

test("opening a row's kebab menu and clicking Delete calls onDelete with the threadId", async () => {
  const onDelete = setup();
  const triggers = screen.getAllByRole("button", { name: /conversation options/i });
  expect(triggers).toHaveLength(2);
  // Radix opens the menu on keyboard activation (avoids jsdom pointer-capture).
  triggers[0].focus();
  fireEvent.keyDown(triggers[0], { key: "Enter" });
  const del = await screen.findByRole("menuitem", { name: /delete/i });
  fireEvent.click(del);
  expect(onDelete).toHaveBeenCalledWith("t1");
});
