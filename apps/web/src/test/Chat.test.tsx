import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { vi } from "vitest";
import { getFunctionName } from "convex/server";
import Chat from "@/features/chat/Chat";
import { useUIMessages } from "@convex-dev/agent/react";
import { api } from "../../convex/_generated/api";

function renderChat() {
  return render(
    <MemoryRouter>
      <Chat />
    </MemoryRouter>,
  );
}

const sendMessage = vi.fn(() => Promise.resolve());
const deleteThreadMock = vi.fn(() => Promise.resolve());

vi.mock("@/features/documents/content-hash", () => ({
  hashFile: vi.fn(async () => "hash-abc"),
  sha256Hex: vi.fn(async () => "hash-abc"),
}));

vi.mock("convex/react", () => ({
  useQuery: (q: Parameters<typeof getFunctionName>[0]) => {
    if (getFunctionName(q) === getFunctionName(api.documents.list))
      return [
        {
          _id: "d1",
          filename: "report.pdf",
          kind: "pdf",
          status: "ready",
          sizeBytes: 10,
          contentHash: "hash-abc",
          createdAt: 1,
        },
      ];
    if (getFunctionName(q) === getFunctionName(api.settings.getSettings))
      return { modelId: "openai/gpt-4o-mini" };
    return [{ _id: "row1", threadId: "thread1", title: "Q3 planning", createdAt: 1 }];
  },
  useMutation: (m?: Parameters<typeof getFunctionName>[0]) => {
    if (m && getFunctionName(m) === getFunctionName(api.chat.deleteThread))
      return deleteThreadMock;
    return vi.fn(() => Promise.resolve());
  },
  useAction: () => sendMessage,
}));

vi.mock("@convex-dev/agent/react", () => ({
  useUIMessages: vi.fn(),
  useSmoothText: (text: string) => [text, { cursor: text.length, isStreaming: false }],
}));

const mockedUseUIMessages = vi.mocked(useUIMessages);

const baseMessages = {
  results: [
    {
      key: "m1",
      role: "user",
      text: "What does the Q3 doc say?",
      parts: [{ type: "text", text: "What does the Q3 doc say?" }],
      status: "success",
      order: 1,
      stepOrder: 1,
    },
    {
      key: "m2",
      role: "assistant",
      text: "Revenue grew 12%.",
      parts: [
        { type: "tool-searchKnowledge", state: "output-available" },
        { type: "text", text: "Revenue grew 12%." },
      ],
      status: "success",
      order: 2,
      stepOrder: 1,
    },
  ],
  status: "Exhausted" as const,
  loadMore: vi.fn(),
};

beforeEach(() => {
  mockedUseUIMessages.mockReturnValue(baseMessages as any);
});

test("renders thread list, streamed messages, and the attach input", () => {
  renderChat();
  // The active conversation's title renders in the rail and in the header, so
  // it legitimately appears more than once — assert it's present at all.
  expect(screen.getAllByText("Q3 planning").length).toBeGreaterThan(0);
  expect(screen.getByRole("button", { name: /new chat/i })).toBeInTheDocument();
  expect(screen.getByText("What does the Q3 doc say?")).toBeInTheDocument();
  expect(screen.getByText("Revenue grew 12%.")).toBeInTheDocument();
  expect(screen.getByLabelText(/attach/i)).toBeInTheDocument();
});

test("typing a message and sending calls the send action with the thread id", async () => {
  renderChat();
  const textarea = screen.getByPlaceholderText(/ask about your documents/i);
  fireEvent.change(textarea, { target: { value: "Summarize the doc" } });
  fireEvent.click(screen.getByRole("button", { name: /^send$/i }));

  await waitFor(() => {
    expect(sendMessage).toHaveBeenCalledWith({
      threadId: "thread1",
      text: "Summarize the doc",
      pinnedSourceIds: [],
    });
  });
});

test("shows a searching-documents affordance while a tool call is in progress", () => {
  mockedUseUIMessages.mockReturnValue({
    results: [
      {
        key: "m1",
        role: "assistant",
        text: "",
        parts: [{ type: "tool-searchKnowledge", state: "input-available" }],
        status: "streaming",
        order: 1,
        stepOrder: 1,
      },
    ],
    status: "Exhausted" as const,
    loadMore: vi.fn(),
  } as any);

  renderChat();
  expect(screen.getByText(/searched your knowledge/i)).toBeInTheDocument();
});

beforeAll(() => {
  // jsdom has no layout / scrollTo; stub so the hook's scroll calls are spyable.
  Element.prototype.scrollTo = vi.fn() as unknown as typeof Element.prototype.scrollTo;
  // Radix menus probe pointer-capture + scroll APIs jsdom doesn't implement.
  Element.prototype.hasPointerCapture = vi.fn(() => false);
  Element.prototype.scrollIntoView = vi.fn();
});

test("scrolls to bottom after sending a message", async () => {
  mockedUseUIMessages.mockReturnValue(baseMessages as any);
  const scrollTo = vi.spyOn(Element.prototype, "scrollTo");
  renderChat();

  const box = screen.getByPlaceholderText(/Ask about your documents/i);
  fireEvent.change(box, { target: { value: "Hello there" } });
  fireEvent.keyDown(box, { key: "Enter" });

  await waitFor(() => expect(scrollTo).toHaveBeenCalled());
});

test("attaching a duplicate opens the dialog; Use existing pins without re-uploading", async () => {
  mockedUseUIMessages.mockReturnValue(baseMessages as any);
  renderChat();

  const input = document.querySelector('input[type="file"]') as HTMLInputElement;
  const file = new File([new Uint8Array([1])], "report.pdf", { type: "application/pdf" });
  fireEvent.change(input, { target: { files: [file] } });

  await screen.findByText("You already have this file");
  fireEvent.click(screen.getByRole("button", { name: /use existing/i }));

  // The existing document is now attached as a chip (rendered by AttachmentCard).
  await waitFor(() =>
    expect(screen.getAllByText("report.pdf").length).toBeGreaterThan(0),
  );
});

test("deleting a conversation confirms then calls deleteThread", async () => {
  mockedUseUIMessages.mockReturnValue(baseMessages as any);
  deleteThreadMock.mockClear();
  renderChat();

  // Open the active row's kebab (mocked listThreads returns thread "thread1").
  const trigger = screen.getAllByRole("button", { name: /conversation options/i })[0];
  trigger.focus();
  fireEvent.keyDown(trigger, { key: "Enter" });
  fireEvent.click(await screen.findByRole("menuitem", { name: /delete/i }));

  // Confirm dialog appears; confirm it.
  await screen.findByText(/delete conversation/i);
  fireEvent.click(screen.getByRole("button", { name: /^delete$/i }));

  await waitFor(() =>
    expect(deleteThreadMock).toHaveBeenCalledWith({ threadId: "thread1" }),
  );
});
