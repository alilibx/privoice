import { useCallback, useRef, useState } from "react";

// How close (px) to the bottom still counts as "at the bottom".
const THRESHOLD = 64;

/**
 * Stick-to-bottom scroll behavior for a scrollable container.
 *
 * Attach `ref` to the scroll element and `onScroll` to its onScroll. Call
 * `stick()` whenever content changes to follow the stream — it only scrolls
 * if the user was already at the bottom (tracked from the last scroll event
 * via a ref mirror, so newly appended content can't flip the check first, and
 * the callback never reads a stale value). `scrollToBottom()` forces a scroll
 * (used for the user's own send and the "jump to latest" pill).
 */
export function useStickToBottom<T extends HTMLElement>() {
  const ref = useRef<T | null>(null);
  const [atBottom, setAtBottom] = useState(true);
  const atBottomRef = useRef(true);

  const set = useCallback((v: boolean) => {
    atBottomRef.current = v;
    setAtBottom(v);
  }, []);

  const computeAtBottom = useCallback(() => {
    const el = ref.current;
    if (!el) return true;
    return el.scrollHeight - el.scrollTop - el.clientHeight <= THRESHOLD;
  }, []);

  const onScroll = useCallback(() => {
    set(computeAtBottom());
  }, [computeAtBottom, set]);

  const scrollToBottom = useCallback(
    (behavior: ScrollBehavior = "auto") => {
      const el = ref.current;
      if (!el) return;
      el.scrollTo({ top: el.scrollHeight, behavior });
      set(true);
    },
    [set],
  );

  const stick = useCallback(() => {
    if (atBottomRef.current) scrollToBottom("auto");
  }, [scrollToBottom]);

  return { ref, atBottom, onScroll, scrollToBottom, stick };
}
