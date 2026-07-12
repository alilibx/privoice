import { createContext, useContext } from "react";

/**
 * Lets any routed page open the app's navigation drawer on small screens
 * (e.g. the chat/page mobile header's hamburger). AppShell provides the real
 * implementation; the no-op default keeps components renderable in isolation
 * (unit tests) without an AppShell ancestor.
 */
export const AppShellContext = createContext<{ openNav: () => void }>({
  openNav: () => {},
});

export function useAppShell() {
  return useContext(AppShellContext);
}
