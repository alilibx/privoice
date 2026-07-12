import { createContext, useContext } from "react";

/**
 * Lets routed pages drive the app's navigation sidebar:
 *  - `openNav`  — open the off-canvas drawer on small screens (mobile header).
 *  - `toggleDesktopNav` — hide/show the persistent sidebar on `lg+`.
 *  - `desktopNavHidden` — current desktop state, for toggle-button affordances.
 * AppShell provides the real implementation; the no-op defaults keep components
 * renderable in isolation (unit tests) without an AppShell ancestor.
 */
export const AppShellContext = createContext<{
  openNav: () => void;
  toggleDesktopNav: () => void;
  desktopNavHidden: boolean;
}>({
  openNav: () => {},
  toggleDesktopNav: () => {},
  desktopNavHidden: false,
});

export function useAppShell() {
  return useContext(AppShellContext);
}
