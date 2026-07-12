# Web Redesign (Privoice Cloud) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign `apps/web` into a proper shadcn/ui SaaS app — collapsible sidebar shell, light/dark/system theming, a visible agent activity trace + in-chat document thumbnails, and a Settings page with a cost/quality model picker.

**Architecture:** Presentation-layer restructure of the existing React + Vite + Convex SPA. Vendor shadcn/ui primitives (no CLI), map the mobile app's hand-tuned light/dark scheme into shadcn CSS-variable tokens, and reorganize into a feature-based folder layout behind `react-router-dom`. Backend gains only per-user model selection (`userSettings` + `settings.ts`) which `sendMessage` reads server-side.

**Tech Stack:** React 18, Vite 5, TypeScript (strict), Tailwind 3, shadcn/ui (Radix + cva), lucide-react, react-router-dom, Convex, `@convex-dev/agent`, `@convex-dev/rag`, Vitest + Testing Library.

## Global Constraints

- Work in `apps/web/`. Do not touch `apps/mobile` or `packages/*`.
- Privacy invariant: any online/cloud path is opt-in and server-gated. `OPENROUTER_API_KEY` is server-only (`process.env`), never sent to or logged for the client.
- Security invariant: the generation model id is resolved and validated **server-side** against a fixed allowlist; the client never injects a raw model id into generation. All user-owned rows stay ownership-scoped.
- Tests runnable from task one: after every task, `npm test` (vitest) is green and `tsc -b && vite build` succeeds. Never gate test execution behind deploy.
- Theming is the single source of truth with `apps/mobile/lib/theme.dart` — use those exact hex values.
- Conventional commits. Commit at the end of every task (and at the TDD checkpoints noted).
- TypeScript strict, `noUnusedLocals`/`noUnusedParameters` on — no unused imports.
- Node/tooling commands run from `apps/web/`. Prefix if needed:
  `export PATH="/opt/homebrew/bin:$PATH"`.

## File Structure (target)

```
apps/web/
  components.json                       # shadcn provenance/config (Task 1)
  vite.config.ts                        # + @/ alias (Task 1)
  tsconfig.json                         # + paths (Task 1)
  tailwind.config.js                    # rewritten to CSS-var tokens (Task 1)
  postcss.config.js                     # unchanged
  src/
    index.css                           # light+dark token blocks (Task 1)
    main.tsx                            # wrap in ThemeProvider + BrowserRouter (Task 3)
    App.tsx                             # routes + auth gate (Task 3)
    lib/
      utils.ts                          # cn() (Task 1)
      theme-provider.tsx                # light/dark/system (Task 1)
      file-icons.tsx                    # icon+color by doc kind (Task 4)
      models.ts                         # curated allowlist + ratings (Task 6)
    components/ui/                       # vendored shadcn primitives (Tasks 1-2)
    components/layout/
      AppShell.tsx  Sidebar.tsx  Topbar.tsx  ThemeToggle.tsx  UserMenu.tsx  (Task 3)
    features/
      auth/AuthForm.tsx                  (Task 3)
      chat/Chat.tsx ThreadList.tsx MessageBubble.tsx ToolTrace.tsx
           AttachmentCard.tsx Composer.tsx                        (Task 4)
      meetings/MeetingsList.tsx MeetingCard.tsx NewMeetingDialog.tsx (Task 5)
      documents/DocumentsList.tsx DocumentCard.tsx UploadDropzone.tsx
                StatusBadge.tsx                                    (Task 5)
      settings/SettingsPage.tsx AppearanceSection.tsx ModelSection.tsx
               ModelComparison.tsx                                (Task 7)
    test/                                # existing tests updated + new ones
  convex/
    schema.ts                           # + userSettings table (Task 6)
    settings.ts                         # getSettings/setModel/listModels (Task 6)
    models.shared.ts                    # allowlist shared client+server (Task 6)
    chat.ts                             # sendMessage reads model (Task 6)
    settings.test.ts                    # (Task 6)
```

Legacy `src/components/{AuthForm,Chat,Dashboard,Documents}.tsx` are deleted once their feature replacements land (Tasks 3-5); their tests move under the new paths.

---

### Task 1: Foundation — deps, alias, tokens, theme, base primitives

**Files:**
- Modify: `apps/web/package.json` (deps)
- Create: `apps/web/src/lib/utils.ts`
- Create: `apps/web/src/lib/theme-provider.tsx`
- Modify: `apps/web/vite.config.ts`
- Modify: `apps/web/tsconfig.json`
- Modify: `apps/web/tailwind.config.js`
- Modify: `apps/web/src/index.css`
- Create: `apps/web/components.json`
- Create: `apps/web/src/components/ui/button.tsx`
- Create: `apps/web/src/components/ui/card.tsx`
- Create: `apps/web/src/components/ui/input.tsx`
- Create: `apps/web/src/test/theme-provider.test.tsx`

**Interfaces:**
- Produces: `cn(...classes)` from `@/lib/utils`.
- Produces: `<ThemeProvider defaultTheme?>`, `useTheme() → { theme, resolvedTheme, setTheme }` where `theme: "light" | "dark" | "system"`, `resolvedTheme: "light" | "dark"`, from `@/lib/theme-provider`.
- Produces: `<Button variant? size?>`, `buttonVariants`; `<Card/CardHeader/CardTitle/CardDescription/CardContent/CardFooter>`; `<Input>` from `@/components/ui/*`.

- [ ] **Step 1: Install dependencies**

Run (from `apps/web`):
```bash
npm install react-router-dom class-variance-authority clsx tailwind-merge lucide-react sonner \
  @radix-ui/react-dialog @radix-ui/react-dropdown-menu @radix-ui/react-avatar \
  @radix-ui/react-tooltip @radix-ui/react-scroll-area @radix-ui/react-separator \
  @radix-ui/react-radio-group @radix-ui/react-slot @radix-ui/react-label
npm install -D tailwindcss-animate
```
Expected: installs succeed; `package.json` lists the above.

- [ ] **Step 2: Add `@/` alias**

`vite.config.ts`:
```ts
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "node:path";

export default defineConfig({
  plugins: [react()],
  resolve: { alias: { "@": path.resolve(__dirname, "./src") } },
});
```
In `tsconfig.json` `compilerOptions`, add:
```json
"baseUrl": ".",
"paths": { "@/*": ["./src/*"] }
```

- [ ] **Step 3: Write `cn`**

`src/lib/utils.ts`:
```ts
import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

- [ ] **Step 4: Rewrite Tailwind config to CSS-var tokens**

`tailwind.config.js`:
```js
/** @type {import('tailwindcss').Config} */
export default {
  darkMode: "class",
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        border: "hsl(var(--border))",
        input: "hsl(var(--input))",
        ring: "hsl(var(--ring))",
        background: "hsl(var(--background))",
        foreground: "hsl(var(--foreground))",
        primary: { DEFAULT: "hsl(var(--primary))", foreground: "hsl(var(--primary-foreground))" },
        secondary: { DEFAULT: "hsl(var(--secondary))", foreground: "hsl(var(--secondary-foreground))" },
        destructive: { DEFAULT: "hsl(var(--destructive))", foreground: "hsl(var(--destructive-foreground))" },
        muted: { DEFAULT: "hsl(var(--muted))", foreground: "hsl(var(--muted-foreground))" },
        accent: { DEFAULT: "hsl(var(--accent))", foreground: "hsl(var(--accent-foreground))" },
        popover: { DEFAULT: "hsl(var(--popover))", foreground: "hsl(var(--popover-foreground))" },
        card: { DEFAULT: "hsl(var(--card))", foreground: "hsl(var(--card-foreground))" },
        sidebar: { DEFAULT: "hsl(var(--sidebar))", foreground: "hsl(var(--sidebar-foreground))" },
      },
      borderRadius: { lg: "var(--radius)", md: "calc(var(--radius) - 4px)", sm: "calc(var(--radius) - 8px)" },
    },
  },
  plugins: [require("tailwindcss-animate")],
};
```

- [ ] **Step 5: Rewrite `index.css` with light + dark token blocks (from mobile scheme)**

`src/index.css` (HSL values converted from `apps/mobile/lib/theme.dart`):
```css
@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  :root {
    --background: 201 26% 95%;         /* #EEF3F6 page-bg */
    --foreground: 200 43% 10%;         /* #0F1D24 on-surface */
    --card: 0 0% 100%;                 /* #FFFFFF surface */
    --card-foreground: 200 43% 10%;
    --popover: 0 0% 100%;
    --popover-foreground: 200 43% 10%;
    --primary: 194 77% 31%;            /* #12708D */
    --primary-foreground: 0 0% 100%;
    --secondary: 197 43% 91%;          /* #DDEEF3 */
    --secondary-foreground: 197 82% 25%;
    --muted: 200 30% 95%;              /* #F1F6F8 surfaceContainer */
    --muted-foreground: 198 13% 41%;   /* #5C6E77 on-surface-variant */
    --accent: 195 44% 91%;             /* #E0EFF4 primary-container */
    --accent-foreground: 197 82% 25%;  /* #0C5C76 */
    --destructive: 3 63% 58%;          /* #DB554D */
    --destructive-foreground: 0 0% 100%;
    --border: 200 26% 86%;             /* #DDE7EC outlineVariant */
    --input: 200 26% 86%;
    --ring: 194 77% 31%;
    --sidebar: 0 0% 100%;
    --sidebar-foreground: 200 43% 10%;
    --radius: 0.9rem;                  /* ~18px */
  }
  .dark {
    --background: 200 33% 6%;          /* #0A1216 page-bg dark */
    --foreground: 197 27% 93%;         /* #E9F0F3 */
    --card: 200 32% 10%;               /* #111C22 surface */
    --card-foreground: 197 27% 93%;
    --popover: 200 32% 10%;
    --popover-foreground: 197 27% 93%;
    --primary: 193 57% 56%;            /* #4FB4D1 */
    --primary-foreground: 197 78% 9%;  /* #052029 */
    --secondary: 199 43% 16%;          /* #16323C */
    --secondary-foreground: 194 63% 83%;
    --muted: 200 31% 13%;              /* #16232A surfaceContainer */
    --muted-foreground: 200 15% 63%;   /* #93A6AF */
    --accent: 197 51% 16%;             /* #13323D primary-container */
    --accent-foreground: 194 63% 83%;  /* #B6E4F1 */
    --destructive: 4 79% 68%;          /* #EF736B */
    --destructive-foreground: 0 0% 100%;
    --border: 200 24% 18%;             /* #22333B outlineVariant */
    --input: 200 24% 18%;
    --ring: 193 57% 56%;
    --sidebar: 200 32% 8%;
    --sidebar-foreground: 197 27% 93%;
  }
  * { border-color: hsl(var(--border)); }
  body {
    margin: 0;
    background: hsl(var(--background));
    color: hsl(var(--foreground));
    font-family: system-ui, -apple-system, sans-serif;
  }
}
```
(Note: the old `:root { color-scheme: light }` pin is intentionally removed — the ThemeProvider now owns light/dark.)

- [ ] **Step 6: Add `components.json`**

`components.json`:
```json
{
  "$schema": "https://ui.shadcn.com/schema.json",
  "style": "default",
  "rsc": false,
  "tsx": true,
  "tailwind": { "config": "tailwind.config.js", "css": "src/index.css", "baseColor": "slate", "cssVariables": true },
  "aliases": { "components": "@/components", "utils": "@/lib/utils", "ui": "@/components/ui" }
}
```

- [ ] **Step 7: Write ThemeProvider + failing test**

`src/lib/theme-provider.tsx`:
```tsx
import { createContext, useContext, useEffect, useState } from "react";

type Theme = "light" | "dark" | "system";
type Ctx = { theme: Theme; resolvedTheme: "light" | "dark"; setTheme: (t: Theme) => void };

const ThemeContext = createContext<Ctx | null>(null);
const KEY = "privoice-theme";

function systemDark() {
  return typeof window !== "undefined" && window.matchMedia("(prefers-color-scheme: dark)").matches;
}

export function ThemeProvider({ children, defaultTheme = "system" as Theme }: { children: React.ReactNode; defaultTheme?: Theme }) {
  const [theme, setThemeState] = useState<Theme>(
    () => (typeof localStorage !== "undefined" && (localStorage.getItem(KEY) as Theme)) || defaultTheme,
  );
  const resolvedTheme: "light" | "dark" = theme === "system" ? (systemDark() ? "dark" : "light") : theme;

  useEffect(() => {
    const root = document.documentElement;
    root.classList.toggle("dark", resolvedTheme === "dark");
  }, [resolvedTheme]);

  useEffect(() => {
    if (theme !== "system") return;
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const onChange = () => document.documentElement.classList.toggle("dark", mq.matches);
    mq.addEventListener("change", onChange);
    return () => mq.removeEventListener("change", onChange);
  }, [theme]);

  const setTheme = (t: Theme) => {
    localStorage.setItem(KEY, t);
    setThemeState(t);
  };
  return <ThemeContext.Provider value={{ theme, resolvedTheme, setTheme }}>{children}</ThemeContext.Provider>;
}

export function useTheme() {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error("useTheme must be used within ThemeProvider");
  return ctx;
}
```
`src/test/theme-provider.test.tsx`:
```tsx
import { render, screen, fireEvent } from "@testing-library/react";
import { ThemeProvider, useTheme } from "@/lib/theme-provider";

function Probe() {
  const { resolvedTheme, setTheme } = useTheme();
  return (
    <div>
      <span data-testid="resolved">{resolvedTheme}</span>
      <button onClick={() => setTheme("dark")}>go dark</button>
    </div>
  );
}

test("defaults to light and toggles dark class", () => {
  render(<ThemeProvider defaultTheme="light"><Probe /></ThemeProvider>);
  expect(screen.getByTestId("resolved")).toHaveTextContent("light");
  fireEvent.click(screen.getByText("go dark"));
  expect(document.documentElement.classList.contains("dark")).toBe(true);
  expect(screen.getByTestId("resolved")).toHaveTextContent("dark");
});
```

- [ ] **Step 8: Run the theme test — expect PASS**

Run: `npm test -- theme-provider`
Expected: PASS (1 test). If localStorage persists between tests later, clear it in the test.

- [ ] **Step 9: Vendor `button`, `card`, `input` primitives**

`src/components/ui/button.tsx`:
```tsx
import * as React from "react";
import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:pointer-events-none disabled:opacity-50 [&_svg]:size-4 [&_svg]:shrink-0",
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground hover:bg-primary/90",
        destructive: "bg-destructive text-destructive-foreground hover:bg-destructive/90",
        outline: "border border-input bg-background hover:bg-accent hover:text-accent-foreground",
        secondary: "bg-secondary text-secondary-foreground hover:bg-secondary/80",
        ghost: "hover:bg-accent hover:text-accent-foreground",
        link: "text-primary underline-offset-4 hover:underline",
      },
      size: { default: "h-10 px-4 py-2", sm: "h-9 rounded-md px-3", lg: "h-11 rounded-md px-8", icon: "h-10 w-10" },
    },
    defaultVariants: { variant: "default", size: "default" },
  },
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean;
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, ...props }, ref) => {
    const Comp = asChild ? Slot : "button";
    return <Comp className={cn(buttonVariants({ variant, size, className }))} ref={ref} {...props} />;
  },
);
Button.displayName = "Button";
export { Button, buttonVariants };
```
`src/components/ui/card.tsx` and `src/components/ui/input.tsx`: vendor the **canonical unmodified shadcn/ui `card` and `input` components** (they use `cn` and the token classes above with no changes). For reference, `input.tsx`:
```tsx
import * as React from "react";
import { cn } from "@/lib/utils";

const Input = React.forwardRef<HTMLInputElement, React.ComponentProps<"input">>(
  ({ className, type, ...props }, ref) => (
    <input
      type={type}
      ref={ref}
      className={cn(
        "flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50",
        className,
      )}
      {...props}
    />
  ),
);
Input.displayName = "Input";
export { Input };
```
`card.tsx` (canonical):
```tsx
import * as React from "react";
import { cn } from "@/lib/utils";

const Card = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(({ className, ...p }, ref) => (
  <div ref={ref} className={cn("rounded-lg border bg-card text-card-foreground shadow-sm", className)} {...p} />
));
Card.displayName = "Card";
const CardHeader = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(({ className, ...p }, ref) => (
  <div ref={ref} className={cn("flex flex-col space-y-1.5 p-6", className)} {...p} />
));
CardHeader.displayName = "CardHeader";
const CardTitle = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(({ className, ...p }, ref) => (
  <div ref={ref} className={cn("text-lg font-semibold leading-none tracking-tight", className)} {...p} />
));
CardTitle.displayName = "CardTitle";
const CardDescription = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(({ className, ...p }, ref) => (
  <div ref={ref} className={cn("text-sm text-muted-foreground", className)} {...p} />
));
CardDescription.displayName = "CardDescription";
const CardContent = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(({ className, ...p }, ref) => (
  <div ref={ref} className={cn("p-6 pt-0", className)} {...p} />
));
CardContent.displayName = "CardContent";
const CardFooter = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(({ className, ...p }, ref) => (
  <div ref={ref} className={cn("flex items-center p-6 pt-0", className)} {...p} />
));
CardFooter.displayName = "CardFooter";
export { Card, CardHeader, CardFooter, CardTitle, CardDescription, CardContent };
```

- [ ] **Step 10: Verify build + full test suite**

Run: `npx tsc -b && npm test`
Expected: type-check clean; all existing tests + the new theme test pass. (Existing screens still import old components — untouched here.)

- [ ] **Step 11: Commit**

```bash
git add apps/web/package.json apps/web/package-lock.json apps/web/vite.config.ts apps/web/tsconfig.json \
  apps/web/tailwind.config.js apps/web/src/index.css apps/web/components.json apps/web/src/lib apps/web/src/components/ui apps/web/src/test/theme-provider.test.tsx
git commit -m "feat(web): shadcn foundation — @/ alias, cn, mobile-mirrored light/dark tokens, ThemeProvider, base primitives"
```

---

### Task 2: Vendor remaining shadcn primitives

**Files (create, all under `apps/web/src/components/ui/`):**
`textarea.tsx`, `label.tsx`, `badge.tsx`, `separator.tsx`, `skeleton.tsx`, `avatar.tsx`, `tooltip.tsx`, `dialog.tsx`, `dropdown-menu.tsx`, `scroll-area.tsx`, `radio-group.tsx`, `table.tsx`, `sonner.tsx`
- Create test: `apps/web/src/test/ui-primitives.test.tsx`

**Interfaces:**
- Produces: `<Textarea>`, `<Label>`, `<Badge variant?>` (+`badgeVariants`), `<Separator>`, `<Skeleton>`, `<Avatar/AvatarImage/AvatarFallback>`, `<Tooltip*>`, `<Dialog*>`, `<DropdownMenu*>`, `<ScrollArea>`, `<RadioGroup/RadioGroupItem>`, `<Table*>`, `<Toaster>` (sonner) — all from `@/components/ui/*`.

- [ ] **Step 1: Vendor the canonical shadcn/ui files**

Add each file as the **canonical unmodified shadcn/ui component** (Radix-based, using `cn` and token classes). These are standard copy-paste components; do not customize. Notable exact contents:

`badge.tsx`:
```tsx
import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const badgeVariants = cva(
  "inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-semibold transition-colors focus:outline-none",
  {
    variants: {
      variant: {
        default: "border-transparent bg-primary text-primary-foreground",
        secondary: "border-transparent bg-secondary text-secondary-foreground",
        destructive: "border-transparent bg-destructive text-destructive-foreground",
        outline: "text-foreground",
        success: "border-transparent bg-emerald-500/15 text-emerald-600 dark:text-emerald-400",
      },
    },
    defaultVariants: { variant: "default" },
  },
);

export function Badge({ className, variant, ...props }: React.HTMLAttributes<HTMLDivElement> & VariantProps<typeof badgeVariants>) {
  return <div className={cn(badgeVariants({ variant }), className)} {...props} />;
}
export { badgeVariants };
```
`textarea.tsx`:
```tsx
import * as React from "react";
import { cn } from "@/lib/utils";
const Textarea = React.forwardRef<HTMLTextAreaElement, React.ComponentProps<"textarea">>(
  ({ className, ...props }, ref) => (
    <textarea
      ref={ref}
      className={cn(
        "flex min-h-[60px] w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50",
        className,
      )}
      {...props}
    />
  ),
);
Textarea.displayName = "Textarea";
export { Textarea };
```
`skeleton.tsx`:
```tsx
import { cn } from "@/lib/utils";
export function Skeleton({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("animate-pulse rounded-md bg-muted", className)} {...props} />;
}
```
`sonner.tsx`:
```tsx
import { Toaster as Sonner } from "sonner";
import { useTheme } from "@/lib/theme-provider";
export function Toaster() {
  const { resolvedTheme } = useTheme();
  return <Sonner theme={resolvedTheme} position="bottom-right" richColors />;
}
```
For `label`, `separator`, `skeleton`, `avatar`, `tooltip`, `dialog`, `dropdown-menu`, `scroll-area`, `radio-group`, `table`: use the canonical shadcn/ui source for each (the standard versions wrapping the matching `@radix-ui/react-*` package installed in Task 1). No token or class edits are needed — they already reference `bg-popover`, `text-muted-foreground`, `border`, etc.

- [ ] **Step 2: Write a render smoke test**

`src/test/ui-primitives.test.tsx`:
```tsx
import { render, screen } from "@testing-library/react";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
import { Skeleton } from "@/components/ui/skeleton";

test("core primitives render", () => {
  render(<><Badge variant="success">Ready</Badge><Textarea aria-label="msg" /><Skeleton className="h-4 w-4" /></>);
  expect(screen.getByText("Ready")).toBeInTheDocument();
  expect(screen.getByLabelText("msg")).toBeInTheDocument();
});
```

- [ ] **Step 3: Run test + type-check**

Run: `npx tsc -b && npm test -- ui-primitives`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add apps/web/src/components/ui apps/web/src/test/ui-primitives.test.tsx
git commit -m "feat(web): vendor remaining shadcn/ui primitives"
```

---

### Task 3: App shell + routing + redesigned Auth

**Files:**
- Create: `src/components/layout/{AppShell,Sidebar,Topbar,ThemeToggle,UserMenu}.tsx`
- Create: `src/features/auth/AuthForm.tsx`
- Modify: `src/main.tsx` (ThemeProvider + BrowserRouter + Toaster)
- Modify: `src/App.tsx` (routes + auth gate)
- Delete: `src/components/AuthForm.tsx`
- Move/Update test: `src/test/AuthForm.test.tsx` → import `@/features/auth/AuthForm`
- Create: `src/test/AppShell.test.tsx`

**Interfaces:**
- Consumes: `useTheme` (Task 1), `Button`/`Card`/`Input` (Task 1), `Avatar`/`DropdownMenu`/`Tooltip`/`Separator` (Task 2).
- Produces: `<AppShell>` (renders sidebar + topbar + `<Outlet/>`), `<AuthForm>`. Nav routes: `/chat`, `/meetings`, `/documents`, `/settings`.

- [ ] **Step 1: Redesign AuthForm (move to feature) + update test**

Create `src/features/auth/AuthForm.tsx`: same logic as the current `src/components/AuthForm.tsx` (Password provider, `MIN_PASSWORD = 8`, signIn flow, error surfacing, sign-in/up toggle) rebuilt with `Card`/`CardHeader`/`CardTitle`/`CardContent`, `Input`, `Label`, and `Button`. Keep all `aria-label`s ("Email", "Password") so the existing test selectors still work.
Update `src/test/AuthForm.test.tsx` import to `@/features/auth/AuthForm`. Delete `src/components/AuthForm.tsx`.

- [ ] **Step 2: Run auth test — expect PASS**

Run: `npm test -- AuthForm`
Expected: PASS (existing assertions on email/password fields + toggle).

- [ ] **Step 3: Build Sidebar / Topbar / ThemeToggle / UserMenu**

`ThemeToggle.tsx`: a `DropdownMenu` (or 3-state segmented `Button`s) driving `useTheme().setTheme` with Sun/Moon/Monitor `lucide-react` icons.
`UserMenu.tsx`: `Avatar` (fallback = first letter of email) → `DropdownMenu` with the user's email (read via `useQuery` on an existing "me" source if present, else omit) and a "Sign out" item calling `useAuthActions().signOut()`.
`Sidebar.tsx`: Privoice wordmark; `NavLink`s (react-router) for Chat/Meetings/Documents/Settings with `lucide` icons (`MessageSquare`, `CalendarDays`, `FileText`, `Settings`); active style via `NavLink`'s `isActive`; a collapse toggle button storing `collapsed` in `localStorage` (`privoice-sidebar`); collapsed → icon-only with `Tooltip` labels. Use `bg-sidebar text-sidebar-foreground`, `border-r border-border`.
`Topbar.tsx`: left = current page title (prop or derived from route), right = `<ThemeToggle/>` + `<UserMenu/>`; `border-b border-border`.

- [ ] **Step 4: Build AppShell**

`AppShell.tsx`:
```tsx
import { Outlet } from "react-router-dom";
import Sidebar from "./Sidebar";
import Topbar from "./Topbar";

export default function AppShell() {
  return (
    <div className="flex h-screen bg-background text-foreground">
      <Sidebar />
      <div className="flex min-w-0 flex-1 flex-col">
        <Topbar />
        <main className="min-h-0 flex-1 overflow-y-auto">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
```

- [ ] **Step 5: Wire routing in main.tsx + App.tsx**

`main.tsx`: wrap `<App/>` in `<ThemeProvider>` and `<BrowserRouter>`, and render `<Toaster/>` inside the providers (kept inside `ThemeProvider` since Toaster reads `useTheme`). Keep `ConvexAuthProvider`.
`App.tsx`:
```tsx
import { Authenticated, Unauthenticated, AuthLoading } from "convex/react";
import { Routes, Route, Navigate } from "react-router-dom";
import AppShell from "@/components/layout/AppShell";
import AuthForm from "@/features/auth/AuthForm";
import Chat from "@/features/chat/Chat";
import MeetingsList from "@/features/meetings/MeetingsList";
import DocumentsList from "@/features/documents/DocumentsList";
import SettingsPage from "@/features/settings/SettingsPage";

export default function App() {
  return (
    <>
      <AuthLoading><main className="grid min-h-screen place-items-center">Loading…</main></AuthLoading>
      <Unauthenticated><AuthForm /></Unauthenticated>
      <Authenticated>
        <Routes>
          <Route element={<AppShell />}>
            <Route path="/chat" element={<Chat />} />
            <Route path="/meetings" element={<MeetingsList />} />
            <Route path="/documents" element={<DocumentsList />} />
            <Route path="/settings" element={<SettingsPage />} />
            <Route path="*" element={<Navigate to="/chat" replace />} />
          </Route>
        </Routes>
      </Authenticated>
    </>
  );
}
```
NOTE: `Chat`, `MeetingsList`, `DocumentsList`, `SettingsPage` are created in Tasks 4-7. To keep the build green now, create **temporary stub files** for the three not-yet-built features that render a placeholder (`export default function X() { return <div className="p-6" />; }`), plus import the existing `Chat` from its old path via a thin re-export until Task 4. (Each later task replaces its stub.)

- [ ] **Step 6: Write AppShell nav test**

`src/test/AppShell.test.tsx`: render `<AppShell/>` inside `<MemoryRouter>` + `<ThemeProvider>`, assert the four nav labels (Chat, Meetings, Documents, Settings) are present. Mock `convex/react` (`useQuery`→`undefined`) and `@convex-dev/auth/react` (`useAuthActions`→`{ signOut: vi.fn() }`).

- [ ] **Step 7: Run tests + type-check + build**

Run: `npx tsc -b && npm test && npm run build`
Expected: PASS; SPA builds. (Stubs keep it green.)

- [ ] **Step 8: Commit**

```bash
git add apps/web/src apps/web/src/test
git commit -m "feat(web): SaaS app shell — sidebar/topbar/theme-toggle/user-menu, react-router, redesigned auth"
```

---

### Task 4: Chat redesign — ToolTrace, AttachmentCard, Composer

**Files:**
- Create: `src/features/chat/{Chat,ThreadList,MessageBubble,ToolTrace,AttachmentCard,Composer}.tsx`
- Create: `src/lib/file-icons.tsx`
- Delete: `src/components/Chat.tsx` (and any temporary re-export from Task 3)
- Move/Update test: `src/test/Chat.test.tsx` → import `@/features/chat/Chat`
- Create tests: `src/test/ToolTrace.test.tsx`, `src/test/AttachmentCard.test.tsx`

**Interfaces:**
- Consumes: `useUIMessages`/`useSmoothText` (`@convex-dev/agent/react`), `api.chat.*`, `api.documents.*`, primitives from Tasks 1-2.
- Produces:
  - `type ChatMessage = { key: string; role: string; text: string; status: string; parts: Array<{ type: string; state?: string; input?: unknown; output?: unknown }> }`
  - `<ToolTrace parts={ChatMessage["parts"]} />`
  - `type Attachment = { docId: string; filename: string; kind: string; sizeBytes: number }`
  - `<AttachmentCard attachment={Attachment} status={"parsing"|"ready"|"failed"} />`
  - `fileIcon(kind: string) → { Icon: LucideIcon; className: string }` from `@/lib/file-icons`.

- [ ] **Step 1: file-icons helper**

`src/lib/file-icons.tsx`: map doc `kind` → `{ Icon, className }` using `lucide-react` (`FileText` for pdf/txt/md, `FileType2` for docx, `FileSpreadsheet` for xlsx, `File` fallback) with per-kind color classes (e.g. pdf → `text-red-500`, docx → `text-blue-500`, xlsx → `text-emerald-500`, md/txt → `text-muted-foreground`). Also export `humanSize(bytes: number): string`.

- [ ] **Step 2: ToolTrace — failing test first**

`src/test/ToolTrace.test.tsx`:
```tsx
import { render, screen } from "@testing-library/react";
import ToolTrace from "@/features/chat/ToolTrace";

test("renders a labeled step per tool part and nothing when none", () => {
  const { rerender } = render(
    <ToolTrace parts={[
      { type: "tool-searchDocuments", state: "output-available", input: { query: "Q3 revenue" } },
      { type: "text" },
    ]} />,
  );
  expect(screen.getByText(/searched your documents/i)).toBeInTheDocument();
  expect(screen.getByText(/Q3 revenue/)).toBeInTheDocument();

  rerender(<ToolTrace parts={[{ type: "text" }]} />);
  expect(screen.queryByText(/searched your/i)).not.toBeInTheDocument();
});
```

- [ ] **Step 3: Run — expect FAIL** (`ToolTrace` not found). `npm test -- ToolTrace`.

- [ ] **Step 4: Implement ToolTrace**

`src/features/chat/ToolTrace.tsx`: filter parts to `p.type.startsWith("tool-")`; per step derive label from a `LABELS: Record<string,string>` (`"tool-searchDocuments":"Searched your documents"`, `"tool-searchMeetings":"Searched your meetings"`, default humanizes the suffix); read the query from `part.input?.query`; state → running (Loader2 spin) / done (Check) / error (AlertTriangle) icon from `state` (`output-available`→done, `output-error`→error, else running). Render a bordered `bg-muted/50` block with a small header ("Activity"/"Thinking") and each step as a row; a `<details>`/toggle reveals `String(part.output ?? "")` truncated. Return `null` if no tool parts. Use `Badge`/`Separator` as fits.

- [ ] **Step 5: Run — expect PASS.** `npm test -- ToolTrace`.

- [ ] **Step 6: AttachmentCard — failing test first**

`src/test/AttachmentCard.test.tsx`:
```tsx
import { render, screen } from "@testing-library/react";
import AttachmentCard from "@/features/chat/AttachmentCard";

test("shows filename, size and status by kind", () => {
  render(<AttachmentCard attachment={{ docId: "d1", filename: "Q3.pdf", kind: "pdf", sizeBytes: 2048 }} status="parsing" />);
  expect(screen.getByText("Q3.pdf")).toBeInTheDocument();
  expect(screen.getByText(/2(\.0)? KB/)).toBeInTheDocument();
  expect(screen.getByText(/parsing/i)).toBeInTheDocument();
});
```

- [ ] **Step 7: Run — expect FAIL.** `npm test -- AttachmentCard`.

- [ ] **Step 8: Implement AttachmentCard**

`src/features/chat/AttachmentCard.tsx`: a compact card (`Card` or a `rounded-md border bg-card` div) with `fileIcon(kind)` on the left, filename (truncate) + `humanSize(sizeBytes)` middle, and a status pill on the right: `parsing`→`<Badge variant="secondary">Parsing…</Badge>` (with Loader2), `ready`→`<Badge variant="success">Ready</Badge>`, `failed`→`<Badge variant="destructive">Failed</Badge>`.

- [ ] **Step 9: Run — expect PASS.** `npm test -- AttachmentCard`.

- [ ] **Step 10: Compose the Chat feature**

Split the current `src/components/Chat.tsx` into:
- `ThreadList.tsx`: the left "New chat" + thread buttons (styled with `Button variant="ghost"`, active = `bg-accent text-accent-foreground`; inside a `ScrollArea`).
- `MessageBubble.tsx`: keep `useSmoothText` streaming + the empty-tool-turn guard; render `<ToolTrace parts={message.parts} />` above the text for assistant turns; user bubble `bg-primary text-primary-foreground`, assistant `bg-muted text-foreground`, rounded per tokens.
- `Composer.tsx`: shadcn `Textarea` (auto-grow), attach `Button variant="ghost" size="icon"` (Paperclip / Loader2 busy) hiding the `<input type="file" accept=".pdf,.docx,.xlsx,.txt,.md">`, send `Button` (Send icon; disabled when empty/sending). Preserve Enter-to-send / Shift+Enter.
- `Chat.tsx`: orchestrates — same `useQuery(api.chat.listThreads)`, `createThread`, `sendMessage`, `useUIMessages`, optimistic `pending` echo, auto-select first thread. **Attachment handling:** keep `generateUploadUrl` + `createDocument` (now capturing the returned `documentId`); maintain per-thread session state `attachments: Attachment[]`; on successful upload push `{ docId, filename, kind: extFromName, sizeBytes }`. Render each attachment via `<AttachmentCard>` whose `status` comes from `useQuery(api.documents.list)` looked up by `docId` (reactive → live Parsing→Ready). Toast errors via `sonner`. Add a small read-only active-model label in the chat header (value from `useQuery(api.settings.getSettings)` once Task 6 lands — until then default text "gpt-4o-mini"), linking to `/settings`.
Delete `src/components/Chat.tsx`. Update `src/test/Chat.test.tsx` import path to `@/features/chat/Chat` (keep its mocks; add `api.documents.list` to the `useQuery` mock returning `[]`, and `useAction`/`useMutation` as before). Keep the existing assertions working (thread title, streamed text, attach input present).

- [ ] **Step 11: Run full suite + type-check + build**

Run: `npx tsc -b && npm test && npm run build`
Expected: PASS (Chat, ToolTrace, AttachmentCard, and prior tests).

- [ ] **Step 12: Commit**

```bash
git add apps/web/src
git commit -m "feat(web): chat redesign — agent activity trace, in-chat document thumbnails, shadcn composer"
```

---

### Task 5: Meetings + Documents redesign

**Files:**
- Create: `src/features/meetings/{MeetingsList,MeetingCard,NewMeetingDialog}.tsx`
- Create: `src/features/documents/{DocumentsList,DocumentCard,UploadDropzone,StatusBadge}.tsx`
- Delete: `src/components/{Dashboard,Documents}.tsx` (+ Task 3 stubs)
- Move/Update tests: `src/test/Dashboard.test.tsx` → `src/test/Meetings.test.tsx` (import `@/features/meetings/MeetingsList`); `src/test/Documents.test.tsx` → import `@/features/documents/DocumentsList`

**Interfaces:**
- Consumes: `api.meetings.{list,create,remove}`, `api.documents.{list,generateUploadUrl,create,remove}`, primitives, `file-icons`.
- Produces: `<MeetingsList>`, `<DocumentsList>`, `<StatusBadge status chunkCount error>`.

- [ ] **Step 1: Meetings — update test to new location/shape**

Rename `Dashboard.test.tsx` → `Meetings.test.tsx`, import `@/features/meetings/MeetingsList`. Keep assertions: renders a heading, an add control, lists meeting titles from the mocked `useQuery`, and a delete affordance. Adjust to the new "New meeting" dialog trigger (assert the trigger button "New meeting" exists; opening the dialog and submitting can stay as a fireEvent flow).

- [ ] **Step 2: Run — expect FAIL** (module not found). `npm test -- Meetings`.

- [ ] **Step 3: Implement Meetings**

`MeetingCard.tsx`: `Card` showing title + a `Button variant="ghost" size="icon"` (Trash2) calling `remove`. `NewMeetingDialog.tsx`: shadcn `Dialog` with a titled form → `create({ title, notes: undefined })`. `MeetingsList.tsx`: page container (`mx-auto max-w-3xl p-6`), header "Meetings" + `<NewMeetingDialog/>` trigger, a responsive grid/list of `MeetingCard`, and an empty state ("No meetings yet"). Same Convex calls as `Dashboard.tsx`. Delete `Dashboard.tsx`.

- [ ] **Step 4: Run — expect PASS.** `npm test -- Meetings`.

- [ ] **Step 5: Documents — update test**

Update `Documents.test.tsx` import to `@/features/documents/DocumentsList`; keep assertions (upload affordance present, lists filenames, status text). Adjust status text to the new `StatusBadge` copy ("Ready", "Parsing…", "Failed").

- [ ] **Step 6: Run — expect FAIL.** `npm test -- Documents`.

- [ ] **Step 7: Implement Documents**

`StatusBadge.tsx`: `ready`→`<Badge variant="success">Ready · {chunkCount} chunks</Badge>`, `failed`→`<Badge variant="destructive" title={error}>Failed</Badge>`, else `<Badge variant="secondary">Parsing…</Badge>`. `UploadDropzone.tsx`: a dashed-border drop area (`onDragOver`/`onDrop` + click-to-select hidden input, `accept=".pdf,.docx,.xlsx,.txt,.md"`) calling an `onFile(file)` prop; busy state. `DocumentCard.tsx`: `Card` with `fileIcon(kind)`, filename, `humanSize`, `StatusBadge`, delete (Trash2). `DocumentsList.tsx`: header "Documents", `<UploadDropzone onFile={upload}/>` (upload = existing generateUploadUrl→fetch→create), grid of `DocumentCard`, empty state; toast errors via sonner. Delete `Documents.tsx`.

- [ ] **Step 8: Run — expect PASS.** `npm test -- Documents`.

- [ ] **Step 9: Full suite + type-check + build**

Run: `npx tsc -b && npm test && npm run build`
Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add apps/web/src
git commit -m "feat(web): redesign meetings + documents (cards, dialog, dropzone, status badges)"
```

---

### Task 6: Model selection backend (schema, settings, sendMessage)

**Files:**
- Modify: `convex/schema.ts` (+`userSettings`)
- Create: `convex/models.shared.ts`
- Create: `convex/settings.ts`
- Modify: `convex/chat.ts` (`sendMessage` resolves model)
- Create test: `convex/settings.test.ts`

**Interfaces:**
- Produces (shared): `MODEL_ALLOWLIST: readonly string[]`, `DEFAULT_MODEL = "openai/gpt-4o-mini"`, `MODEL_META: Record<string, { name: string; toolRating: "Good"|"Strong"|"Best"; ragRating: "Good"|"Strong"|"Best" }>`, `isAllowedModel(id: string): boolean` from `convex/models.shared.ts`.
- Produces (settings): `api.settings.getSettings` → `{ modelId: string }`; `api.settings.setModel({ modelId })`; `api.settings.listModels` (action) → `Array<{ id; name; promptPrice: number|null; completionPrice: number|null; toolRating; ragRating }>`.
- Consumed by: Task 7 (Settings UI) and Task 4's chat header label.

- [ ] **Step 1: Shared allowlist module**

`convex/models.shared.ts` — no Convex imports (safe to import from both client `src/` and server `convex/`):
```ts
export const DEFAULT_MODEL = "openai/gpt-4o-mini";

export const MODEL_META = {
  "openai/gpt-4o-mini": { name: "GPT-4o mini", toolRating: "Good", ragRating: "Good" },
  "google/gemini-2.5-flash": { name: "Gemini 2.5 Flash", toolRating: "Good", ragRating: "Strong" },
  "anthropic/claude-haiku-4.5": { name: "Claude Haiku 4.5", toolRating: "Strong", ragRating: "Strong" },
  "anthropic/claude-sonnet-5": { name: "Claude Sonnet 5", toolRating: "Best", ragRating: "Best" },
  "openai/gpt-5.4": { name: "GPT-5.4", toolRating: "Strong", ragRating: "Strong" },
  "openai/gpt-5.5": { name: "GPT-5.5", toolRating: "Best", ragRating: "Best" },
} as const satisfies Record<string, { name: string; toolRating: string; ragRating: string }>;

export const MODEL_ALLOWLIST = Object.keys(MODEL_META);
export function isAllowedModel(id: string): boolean {
  return (MODEL_ALLOWLIST as string[]).includes(id);
}
```

- [ ] **Step 2: Add `userSettings` to schema**

In `convex/schema.ts`, add:
```ts
  userSettings: defineTable({
    userId: v.id("users"),
    modelId: v.string(),
    updatedAt: v.number(),
  }).index("by_user", ["userId"]),
```

- [ ] **Step 3: settings.test.ts — failing tests first**

`convex/settings.test.ts` (convex-test, mirroring `meetings.test.ts` auth setup):
```ts
// getSettings returns DEFAULT_MODEL when unset
// setModel persists an allowlisted id (getSettings reflects it)
// setModel throws ConvexError for a non-allowlisted id (e.g. "evil/model")
```
Write these three as real convex-test cases (create an authed identity, call the functions via `t.mutation`/`t.query`, assert results and the thrown error).

- [ ] **Step 4: Run — expect FAIL** (`settings` not found). `npm test -- settings`.

- [ ] **Step 5: Implement settings.ts**

`convex/settings.ts`:
- `getSettings` (query): resolve `getAuthUserId`; read `userSettings` by `by_user`; return `{ modelId: row?.modelId ?? DEFAULT_MODEL }`.
- `setModel` (mutation, args `{ modelId: v.string() }`): require auth; `if (!isAllowedModel(modelId)) throw new ConvexError("Unsupported model")`; upsert the user's row (`patch` if exists else `insert`) with `updatedAt: Date.now()`.
- `listModels` (action): require auth; `fetch("https://openrouter.ai/api/v1/models")` with `Authorization: Bearer ${process.env.OPENROUTER_API_KEY}`; build a price map by id (`data[].pricing.prompt|completion`, ×1e6 → per-1M, numeric or null); return `MODEL_ALLOWLIST.map(id => ({ id, ...MODEL_META[id], promptPrice, completionPrice }))`. Wrap the fetch in try/catch → on failure return the same array with `promptPrice/completionPrice = null` (fail-soft).

- [ ] **Step 6: Run — expect PASS.** `npm test -- settings`.

- [ ] **Step 7: sendMessage resolves model server-side**

In `convex/chat.ts` `sendMessage`, before `streamText`, resolve the model from the caller's settings (action ctx → `ctx.runQuery`). Add an internal query `getUserModel` (or reuse `getSettings` logic via an internal query keyed by userId) returning the validated model id (fail-closed to `DEFAULT_MODEL` via `isAllowedModel`). Then:
```ts
import { openrouter } from "./openrouter";
import { isAllowedModel, DEFAULT_MODEL } from "./models.shared";
// ...
const raw = await ctx.runQuery(internal.chat.getUserModel, { userId });
const modelId = isAllowedModel(raw) ? raw : DEFAULT_MODEL;
const result = await thread.streamText(
  { prompt: text, model: openrouter.chat(modelId) },
  { saveStreamDeltas: true },
);
```
Add `getUserModel` as an `internalQuery({ args: { userId: v.id("users") }, handler })` reading `userSettings` by `by_user`. Keep `stopWhen`/tools behavior from `agent.ts` (thread inherits the agent config; only the model is overridden per call).

- [ ] **Step 8: Run chat + settings tests + type-check**

Run: `npx tsc -b && npm test -- chat settings`
Expected: PASS. (Chat action tests that don't exercise generation are unaffected; the model override is inert under convex-test's headless agent.)

- [ ] **Step 9: Commit**

```bash
git add apps/web/convex apps/web/src
git commit -m "feat(web): per-user model selection — userSettings, settings API (allowlist-validated), sendMessage model override"
```

---

### Task 7: Settings UI — appearance + model comparison

**Files:**
- Create: `src/features/settings/{SettingsPage,AppearanceSection,ModelSection,ModelComparison}.tsx`
- Modify: `src/features/chat/Chat.tsx` (header active-model label → real `getSettings`)
- Delete: Task 3 `SettingsPage` stub
- Create test: `src/test/ModelComparison.test.tsx`

**Interfaces:**
- Consumes: `api.settings.{getSettings,setModel,listModels}`, `useTheme`, primitives (`RadioGroup`, `Table`, `Card`, `Badge`, `Skeleton`, `Button`).
- Produces: `<SettingsPage>` (route `/settings`), `<ModelComparison models selectedId onSelect>`.

- [ ] **Step 1: ModelComparison — failing test first**

`src/test/ModelComparison.test.tsx`:
```tsx
import { render, screen, fireEvent } from "@testing-library/react";
import ModelComparison from "@/features/settings/ModelComparison";

test("renders rows and calls onSelect", () => {
  const onSelect = vi.fn();
  render(
    <ModelComparison
      models={[
        { id: "openai/gpt-4o-mini", name: "GPT-4o mini", promptPrice: 0.15, completionPrice: 0.6, toolRating: "Good", ragRating: "Good" },
        { id: "anthropic/claude-sonnet-5", name: "Claude Sonnet 5", promptPrice: 2, completionPrice: 10, toolRating: "Best", ragRating: "Best" },
      ]}
      selectedId="openai/gpt-4o-mini"
      onSelect={onSelect}
    />,
  );
  expect(screen.getByText("GPT-4o mini")).toBeInTheDocument();
  expect(screen.getByText("Claude Sonnet 5")).toBeInTheDocument();
  fireEvent.click(screen.getByText("Claude Sonnet 5"));
  expect(onSelect).toHaveBeenCalledWith("anthropic/claude-sonnet-5");
});
```

- [ ] **Step 2: Run — expect FAIL.** `npm test -- ModelComparison`.

- [ ] **Step 3: Implement ModelComparison**

`ModelComparison.tsx`: props `{ models: ModelRow[]; selectedId: string; onSelect: (id: string) => void }`. Render a `RadioGroup` (value=selectedId, onValueChange=onSelect) as a responsive set of selectable rows/cards, each showing name, price (`$${promptPrice?.toFixed(2) ?? "—"} / $${completionPrice?.toFixed(2) ?? "—"} per 1M`), and `Badge`s for Tool-calling + RAG ratings (map Best→`default`, Strong→`secondary`, Good→`outline`). The whole row is clickable → `onSelect(id)`; selected row gets a ring/`border-primary`. (On desktop a `Table` layout is fine; keep the click-to-select behavior the test asserts.)

- [ ] **Step 4: Run — expect PASS.** `npm test -- ModelComparison`.

- [ ] **Step 5: AppearanceSection + ModelSection + SettingsPage**

`AppearanceSection.tsx`: `Card` with a 3-way theme control (`RadioGroup` or segmented `Button`s: Light/Dark/System) bound to `useTheme()`.
`ModelSection.tsx`: `Card`; `const models = useQuery`... actually `listModels` is an **action** → call via `useAction` in an effect into state, showing `Skeleton` rows while loading; `getSettings` (`useQuery`) for `selectedId`; `setModel` (`useMutation`) on select (toast confirmation). Renders `<ModelComparison>`.
`SettingsPage.tsx`: page container, heading "Settings", stacks `<AppearanceSection/>` + `<ModelSection/>`. Replace the Task 3 stub.

- [ ] **Step 6: Wire chat header active-model label**

In `Chat.tsx`, replace the placeholder label with `useQuery(api.settings.getSettings)?.modelId` mapped through `MODEL_META[id]?.name`, shown as a small muted `Button variant="link"` linking to `/settings`.

- [ ] **Step 7: Full suite + type-check + build**

Run: `npx tsc -b && npm test && npm run build`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add apps/web/src
git commit -m "feat(web): settings page — appearance + model comparison (live pricing + curated ratings)"
```

---

### Task 8: Verification, cleanup, STATUS.md

**Files:**
- Modify: `STATUS.md`
- Possibly: any lingering old files/tests

**Interfaces:** none (integration/verification task).

- [ ] **Step 1: Confirm no orphans**

Run: `ls apps/web/src/components` — expect only `ui/` and `layout/`. Confirm `AuthForm.tsx`, `Chat.tsx`, `Dashboard.tsx`, `Documents.tsx` are gone from `src/components/`. `grep -rn "components/Chat\|components/Dashboard\|components/Documents\|components/AuthForm" apps/web/src` returns nothing.

- [ ] **Step 2: Full green gate**

Run (from repo root):
```bash
export PATH="/opt/homebrew/bin:$HOME/.pub-cache/bin:$PATH"
cd apps/web && npx tsc -b && npm test && npm run build
```
Expected: type-check clean, all Vitest suites pass, `dist/` builds.

- [ ] **Step 3: Browser smoke (manual)**

`npm run dev`, sign in, and verify: sidebar nav + collapse; theme toggle light/dark/system; chat shows the activity trace on a tool-using answer and an attachment card (Parsing→Ready) after uploading a PDF in-chat; meetings add/delete via dialog; documents dropzone upload + status badges; settings model list shows live prices and switching persists (reload keeps it) and the chat header label updates.

- [ ] **Step 4: Update STATUS.md**

Add a completed web slice (e.g. **C3 — web redesign (shadcn SaaS shell + agent trace + doc thumbnails + model picker)** ✅) under the Privoice Cloud workstream; update "Last updated" to the completion date and the "What's next" line. Mark ✅ only after Steps 2-3 pass.

- [ ] **Step 5: Commit**

```bash
git add STATUS.md
git commit -m "docs(status): web redesign (C3) complete + verified"
```

---

## Self-Review

**Spec coverage:**
- shadcn + theming from mobile scheme → Task 1 ✅
- Feature folder structure + react-router + `@/` alias + deps → Tasks 1, 3 ✅
- Collapsible sidebar shell, topbar, user menu, theme toggle, redesigned auth → Task 3 ✅
- Agent activity trace (from `parts`) → Task 4 ✅
- In-chat document thumbnail (file-type card + live status) → Task 4 ✅
- Composer redesign → Task 4 ✅
- Meetings + Documents redesign (dialog, dropzone, status badges) → Task 5 ✅
- Settings route; Appearance + Model sections → Tasks 6-7 ✅
- Curated allowlist (gpt-4o-mini, gemini-2.5-flash, claude-haiku-4.5, claude-sonnet-5, gpt-5.4, gpt-5.5) with live pricing + curated ratings → Tasks 6-7 ✅
- `userSettings` table + `settings.ts` (getSettings/setModel allowlist-validated/listModels) → Task 6 ✅
- `sendMessage` server-side model resolution, fail-closed → Task 6 ✅
- Security invariant (server-side validation, key server-only) → Task 6, Global Constraints ✅
- Chat header active-model label → Tasks 4 (placeholder) → 7 (real) ✅
- Tests kept green + new tests (ToolTrace, AttachmentCard, ModelComparison, settings) → all tasks ✅
- STATUS.md update → Task 8 ✅

**Placeholder scan:** Standard shadcn primitives are referenced as "canonical unmodified files" (external, well-defined) with exact code given for the customized/non-obvious ones (button variants, badge success variant, tokens, ThemeProvider, ToolTrace, AttachmentCard, models.shared, settings). No TBD/TODO left. Task 3 uses explicit temporary stubs (with exact placeholder body) to keep the build green between tasks — resolved by Tasks 4-7.

**Type consistency:** `ChatMessage`/`Attachment` shapes defined in Task 4 interfaces match their tests; `MODEL_META`/`MODEL_ALLOWLIST`/`DEFAULT_MODEL`/`isAllowedModel` names are consistent across Tasks 6-7 and chat.ts; `getUserModel` internal query named consistently in Task 6; `ModelRow` fields (`id,name,promptPrice,completionPrice,toolRating,ragRating`) match between `listModels` (Task 6) and `ModelComparison` (Task 7 test + impl).
