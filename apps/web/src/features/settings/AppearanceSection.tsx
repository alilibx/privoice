import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { useTheme } from "@/lib/theme-provider";

const OPTIONS = [
  { value: "light", label: "Light" },
  { value: "dark", label: "Dark" },
  { value: "system", label: "System" },
] as const;

export default function AppearanceSection() {
  const { theme, setTheme } = useTheme();

  return (
    <Card>
      <CardHeader>
        <CardTitle>Appearance</CardTitle>
        <CardDescription>Choose how Privoice looks on this device.</CardDescription>
      </CardHeader>
      <CardContent>
        <div className="inline-flex rounded-md border p-1">
          {OPTIONS.map((opt) => (
            <Button
              key={opt.value}
              type="button"
              size="sm"
              variant={theme === opt.value ? "default" : "ghost"}
              onClick={() => setTheme(opt.value)}
              aria-pressed={theme === opt.value}
            >
              {opt.label}
            </Button>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}
