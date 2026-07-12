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

vi.mock("convex/react", () => ({
  useQuery: (q: Parameters<typeof getFunctionName>[0]) => {
    if (getFunctionName(q) === getFunctionName(api.documents.list)) return [];
    if (getFunctionName(q) === getFunctionName(api.settings.getSettings))
      return { modelId: "openai/gpt-4o-mini" };
    return [{ _id: "row1", threadId: "thread1", title: "Q3 planning", createdAt: 1 }];
  },
  useMutation: () => vi.fn(() => Promise.resolve()),
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
        { type: "tool-searchDocuments", state: "output-available" },
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
        parts: [{ type: "tool-searchDocuments", state: "input-available" }],
        status: "streaming",
        order: 1,
        stepOrder: 1,
      },
    ],
    status: "Exhausted" as const,
    loadMore: vi.fn(),
  } as any);

  renderChat();
  expect(screen.getByText(/searched your documents/i)).toBeInTheDocument();
});
