import { renderHook, act } from "@testing-library/react";
import { vi, expect, test } from "vitest";
import { useStickToBottom } from "@/features/chat/use-stick-to-bottom";

// jsdom does no layout, so fake an element exposing the scroll metrics the
// hook reads plus a spyable scrollTo.
function fakeEl(over: Partial<Record<"scrollHeight" | "clientHeight" | "scrollTop", number>> = {}) {
  return {
    scrollHeight: 1000,
    clientHeight: 300,
    scrollTop: 700, // 1000 - 700 - 300 = 0 → at bottom
    scrollTo: vi.fn(),
    ...over,
  };
}

test("atBottom is true within threshold, false when scrolled up", () => {
  const { result } = renderHook(() => useStickToBottom<HTMLDivElement>());
  const el = fakeEl();
  // @ts-expect-error assigning a fake element to the ref for the test
  result.current.ref.current = el;

  act(() => result.current.onScroll());
  expect(result.current.atBottom).toBe(true);

  el.scrollTop = 0; // 1000 - 0 - 300 = 700 > 64 → not at bottom
  act(() => result.current.onScroll());
  expect(result.current.atBottom).toBe(false);
});

test("stick scrolls only when at bottom; scrollToBottom always scrolls", () => {
  const { result } = renderHook(() => useStickToBottom<HTMLDivElement>());
  const el = fakeEl();
  // @ts-expect-error fake element
  result.current.ref.current = el;

  act(() => result.current.onScroll()); // at bottom
  act(() => result.current.stick());
  expect(el.scrollTo).toHaveBeenCalledTimes(1);

  el.scrollTop = 0;
  act(() => result.current.onScroll()); // scrolled up
  el.scrollTo.mockClear();
  act(() => result.current.stick());
  expect(el.scrollTo).not.toHaveBeenCalled();

  act(() => result.current.scrollToBottom("smooth"));
  expect(el.scrollTo).toHaveBeenCalledWith({ top: 1000, behavior: "smooth" });
  expect(result.current.atBottom).toBe(true);
});
