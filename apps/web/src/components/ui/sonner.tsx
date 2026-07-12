import { Toaster as Sonner } from "sonner";
import { useTheme } from "@/lib/theme-provider";
export function Toaster() {
  const { resolvedTheme } = useTheme();
  return <Sonner theme={resolvedTheme} position="bottom-right" richColors />;
}
