# O1 — Convex + Convex Auth + Vite web scaffold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up `apps/web` — a React + Vite SPA on Convex where a user signs up / logs in / logs out (email+password) and sees an authenticated dashboard that lists and creates their own meetings (title+notes), with every backend call identity-gated.

**Architecture:** New JS project `apps/web` (Vite/React/TS + Tailwind). Convex is the backend, colocated in `apps/web/convex/` (standard Vite layout; `src/` imports `../convex/_generated/api`). Auth via `@convex-dev/auth` Password provider. Data: `authTables` + a `meetings` table indexed `by_user`; functions resolve the caller with `getAuthUserId` and reject unauthenticated calls. Mobile is untouched (a pure client later, O5).

**Tech Stack:** React 18, Vite, TypeScript, Tailwind CSS, `convex`, `@convex-dev/auth`, `@auth/core@0.41.1`; testing with `convex-test` + `vitest` + `@testing-library/react`. Package manager: npm (local to `apps/web`; melos governs Dart only).

## Global Constraints

Security/privacy is the top priority (per standing directive) — these bind every task:
- **Every Convex query/mutation resolves `const userId = await getAuthUserId(ctx)` and throws `ConvexError("Not authenticated")` when null.** No unauthenticated data path.
- **`meetings` rows are keyed by `userId`; reads/writes/deletes are scoped to the caller.** A user must never read or mutate another user's row. This is **tested for isolation**, not assumed.
- **No secrets in code or logs.** Deployment URL only in `apps/web/.env.local` (gitignored) as `VITE_CONVEX_URL`. Auth signing keys (`JWT_PRIVATE_KEY`/JWKS) are Convex **deployment env vars** provisioned by the user's account-bound setup — never committed, printed, or logged. The agent never handles these secrets.
- **Gitignore** `node_modules/`, `apps/web/convex/_generated/`, `apps/web/.env.local`, `apps/web/dist/`.
- **Minimal data:** meetings store only `userId`, `title`, `notes?`, `createdAt`, `status`. No audio/transcript/PII beyond the account email Convex Auth holds.
- **Field names mirror the mobile `Meeting`** (`title`, `createdAt`, `status`) for later parity; do NOT model transcript/minutes/actionItems yet (YAGNI).
- **`/security-review` on the O1 diff is part of definition-of-done** before merge.
- Deployment: `colorless-mammoth-659` (`https://colorless-mammoth-659.convex.cloud`). Conventional commits.

**Account-bound steps (the USER runs these; agent scaffolds code + hands exact commands):**
1. `cd apps/web && npm install`
2. `npx @convex-dev/auth` — provisions auth signing keys as deployment env vars (links the existing `colorless-mammoth-659` deployment).
3. `npx convex dev` (or `--once`) — codegen (`convex/_generated/`) + push functions.
Backend tests (`convex-test`) and web component tests (`vitest`) run **after** step 3 produces `_generated/`.

**Verify commands (from `apps/web`):**
- Types: `npx tsc --noEmit` · Build: `npm run build` · Tests: `npm run test` (vitest, runs both `convex/` and `src/` tests)
- Env (Dart tooling, unchanged for Flutter): not needed for `apps/web`; Node is at `/usr/local/bin/node` (v22).

---

## File Structure

```
apps/web/
  package.json  vite.config.ts  tsconfig.json  tsconfig.node.json
  tailwind.config.js  postcss.config.js  index.html
  .gitignore  .env.local(gitignored)  README.md
  vitest.config.ts
  src/
    main.tsx          # ConvexAuthProvider(ConvexReactClient(VITE_CONVEX_URL))
    App.tsx           # <AuthLoading>/<Unauthenticated>/<Authenticated>
    index.css         # Tailwind + calm-teal CSS vars
    theme.ts          # calm-teal token constants (mirrors mobile)
    components/AuthForm.tsx
    components/Dashboard.tsx
    test/AuthForm.test.tsx
    test/setup.ts
  convex/
    schema.ts         # authTables + meetings
    auth.ts           # convexAuth({providers:[Password]})
    auth.config.ts    # provider config (also written/checked by auth setup)
    http.ts           # auth.addHttpRoutes(http)
    meetings.ts       # list / create / remove (identity-gated)
    meetings.test.ts  # convex-test authorization tests
    _generated/       # gitignored (created by `convex dev`/codegen)
```

---

## Task 1: Scaffold `apps/web` (Vite + React + TS + Tailwind + calm-teal) + app shell

**Files:**
- Create: `apps/web/{package.json, vite.config.ts, vitest.config.ts, tsconfig.json, tsconfig.node.json, tailwind.config.js, postcss.config.js, index.html, .gitignore, README.md}`
- Create: `apps/web/src/{main.tsx, App.tsx, index.css, theme.ts, test/setup.ts, test/smoke.test.tsx}`

**Interfaces:**
- Produces: a building, testable Vite React app with the calm-teal palette. Convex wiring is added in later tasks — Task 1's `App.tsx` renders a static placeholder shell so it builds and tests without a backend.

- [ ] **Step 1: Create `package.json`**

```json
{
  "name": "privoice-web",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview",
    "test": "vitest run",
    "convex:dev": "convex dev"
  },
  "dependencies": {
    "convex": "^1.42.1",
    "@convex-dev/auth": "^0.0.87",
    "@auth/core": "0.41.1",
    "react": "^18.3.1",
    "react-dom": "^18.3.1"
  },
  "devDependencies": {
    "@testing-library/jest-dom": "^6.4.0",
    "@testing-library/react": "^16.0.0",
    "@types/react": "^18.3.0",
    "@types/react-dom": "^18.3.0",
    "@vitejs/plugin-react": "^4.3.0",
    "autoprefixer": "^10.4.0",
    "convex-test": "^0.0.35",
    "jsdom": "^25.0.0",
    "postcss": "^8.4.0",
    "tailwindcss": "^3.4.0",
    "typescript": "^5.5.0",
    "vite": "^5.4.0",
    "vitest": "^2.1.0"
  }
}
```
(Exact patch versions resolve on `npm install`; if a listed version is unavailable, take the nearest compatible and note it.)

- [ ] **Step 2: Config files**

`apps/web/vite.config.ts`:
```ts
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
export default defineConfig({ plugins: [react()] });
```
`apps/web/vitest.config.ts`:
```ts
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src/test/setup.ts"],
    // convex-test needs the edge-runtime-ish server env for convex/*.test.ts;
    // use jsdom for src and let convex-test provide its own module env.
    server: { deps: { inline: ["convex-test"] } },
  },
});
```
`apps/web/tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2020", "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"], "module": "ESNext",
    "skipLibCheck": true, "moduleResolution": "Bundler",
    "resolveJsonModule": true, "isolatedModules": true, "noEmit": true,
    "jsx": "react-jsx", "strict": true, "noUnusedLocals": true,
    "noUnusedParameters": true, "noFallthroughCasesInSwitch": true
  },
  "include": ["src", "convex"]
}
```
`apps/web/tsconfig.node.json`:
```json
{ "compilerOptions": { "composite": true, "skipLibCheck": true, "module": "ESNext", "moduleResolution": "Bundler", "allowSyntheticDefaultImports": true }, "include": ["vite.config.ts"] }
```
`apps/web/tailwind.config.js`:
```js
/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  darkMode: "media",
  theme: {
    extend: {
      colors: {
        // calm-teal, mirrored from apps/mobile/lib/theme.dart
        primary: "#12708D",
        "primary-container": "#E0EFF4",
        "on-primary-container": "#0C5C76",
        surface: "#FFFFFF",
        "page-bg": "#EEF3F6",
        "on-surface": "#0F1D24",
        "on-surface-variant": "#5C6E77",
        outline: "#DDE7EC",
      },
      borderRadius: { xl: "18px", lg: "14px" },
    },
  },
  plugins: [],
};
```
`apps/web/postcss.config.js`:
```js
export default { plugins: { tailwindcss: {}, autoprefixer: {} } };
```
`apps/web/index.html`:
```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Privoice</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```
`apps/web/.gitignore`:
```
node_modules/
convex/_generated/
.env.local
dist/
```

- [ ] **Step 3: Theme + styles + app shell**

`apps/web/src/theme.ts`:
```ts
// Calm-teal tokens mirrored from apps/mobile/lib/theme.dart. One source of truth
// for the web palette so the product feels the same across platforms.
export const calmTeal = {
  primary: "#12708D",
  primaryContainer: "#E0EFF4",
  onPrimaryContainer: "#0C5C76",
  pageBg: "#EEF3F6",
  surface: "#FFFFFF",
  onSurface: "#0F1D24",
  onSurfaceVariant: "#5C6E77",
  outline: "#DDE7EC",
} as const;
```
`apps/web/src/index.css`:
```css
@tailwind base;
@tailwind components;
@tailwind utilities;
:root { color-scheme: light dark; }
body { margin: 0; background: theme(colors.page-bg); color: theme(colors.on-surface); font-family: system-ui, -apple-system, sans-serif; }
```
`apps/web/src/App.tsx` (Task-1 placeholder; Convex wiring lands in Task 3):
```tsx
export default function App() {
  return (
    <main className="min-h-screen grid place-items-center p-6">
      <div className="rounded-xl border border-outline bg-surface p-8 text-center">
        <h1 className="text-2xl font-bold text-primary">Privoice</h1>
        <p className="mt-2 text-on-surface-variant">Private meeting notes — web.</p>
      </div>
    </main>
  );
}
```
`apps/web/src/main.tsx` (Task-1 version; provider added in Task 3):
```tsx
import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import "./index.css";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
```

- [ ] **Step 4: Test setup + failing smoke test**

`apps/web/src/test/setup.ts`:
```ts
import "@testing-library/jest-dom";
```
`apps/web/src/test/smoke.test.tsx`:
```tsx
import { render, screen } from "@testing-library/react";
import App from "../App";

test("renders the Privoice shell", () => {
  render(<App />);
  expect(screen.getByRole("heading", { name: "Privoice" })).toBeInTheDocument();
});
```

- [ ] **Step 5: Install, verify RED→GREEN, build**

Run:
```bash
cd apps/web && npm install
npm run test        # smoke test passes
npx tsc --noEmit    # clean
npm run build       # vite build succeeds
```
Expected: test passes, types clean, build emits `dist/`.

- [ ] **Step 6: README + commit**

`apps/web/README.md`: document install/dev/build/test + the three account-bound commands (npm install → `npx @convex-dev/auth` → `npx convex dev`) and that `VITE_CONVEX_URL` goes in `.env.local`.

```bash
git add apps/web
git commit -m "feat(web): scaffold apps/web — Vite+React+TS+Tailwind, calm-teal tokens, app shell"
```

---

## Task 2: Convex backend — schema + identity-gated `meetings` functions + authz tests

**Files:**
- Create: `apps/web/convex/{schema.ts, meetings.ts, meetings.test.ts}`

**Interfaces:**
- Consumes: `getAuthUserId` from `@convex-dev/auth/server`; `authTables`.
- Produces: `api.meetings.list` (query → caller's meetings desc), `api.meetings.create` (mutation `{title, notes?}` → `Id<"meetings">`), `api.meetings.remove` (mutation `{id}` → void). All identity-gated.

> **Depends on the account-bound deploy for `_generated/`.** Write the code + tests now; the RED/GREEN run happens once the user has run `npx convex dev` (Task 5 gate) — OR, if `npx convex codegen` succeeds locally with the linked deployment, run it earlier. State in the report which path was used.

- [ ] **Step 1: Schema**

`apps/web/convex/schema.ts`:
```ts
import { defineSchema, defineTable } from "convex/server";
import { authTables } from "@convex-dev/auth/server";
import { v } from "convex/values";

export default defineSchema({
  ...authTables,
  meetings: defineTable({
    userId: v.id("users"),
    title: v.string(),
    notes: v.optional(v.string()),
    createdAt: v.number(),
    status: v.string(), // "note" in O1 (no audio yet); mirrors mobile status naming
  }).index("by_user", ["userId"]),
});
```

- [ ] **Step 2: Write failing authorization tests**

`apps/web/convex/meetings.test.ts`:
```ts
import { convexTest } from "convex-test";
import { expect, test } from "vitest";
import schema from "./schema";
import { api } from "./_generated/api";

// convex-test loads all backend modules from this glob.
const modules = import.meta.glob("./**/*.ts");

// Seed a user row and return an identity whose subject matches what
// getAuthUserId expects (`${userId}|${sessionId}`).
async function asNewUser(t: ReturnType<typeof convexTest>, email: string) {
  const userId = await t.run(async (ctx) => ctx.db.insert("users", { email }));
  return t.withIdentity({ subject: `${userId}|session_${userId}` });
}

test("create then list returns only the caller's meetings", async () => {
  const t = convexTest(schema, modules);
  const alice = await asNewUser(t, "alice@example.com");
  await alice.mutation(api.meetings.create, { title: "Alice sync" });
  const rows = await alice.query(api.meetings.list, {});
  expect(rows).toHaveLength(1);
  expect(rows[0].title).toBe("Alice sync");
});

test("a user never sees another user's meetings", async () => {
  const t = convexTest(schema, modules);
  const alice = await asNewUser(t, "alice@example.com");
  const bob = await asNewUser(t, "bob@example.com");
  await alice.mutation(api.meetings.create, { title: "Alice private" });
  expect(await bob.query(api.meetings.list, {})).toHaveLength(0);
});

test("remove refuses another user's meeting", async () => {
  const t = convexTest(schema, modules);
  const alice = await asNewUser(t, "alice@example.com");
  const bob = await asNewUser(t, "bob@example.com");
  const id = await alice.mutation(api.meetings.create, { title: "Alice only" });
  await expect(bob.mutation(api.meetings.remove, { id })).rejects.toThrow();
  expect(await alice.query(api.meetings.list, {})).toHaveLength(1);
});

test("unauthenticated calls throw", async () => {
  const t = convexTest(schema, modules);
  await expect(t.query(api.meetings.list, {})).rejects.toThrow();
  await expect(t.mutation(api.meetings.create, { title: "x" })).rejects.toThrow();
});
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd apps/web && npm run test -- meetings`
Expected: FAIL — `api.meetings.*` undefined / `_generated` missing (if so, run codegen first — see the depends-on note) or functions not implemented.

- [ ] **Step 4: Implement the functions**

`apps/web/convex/meetings.ts`:
```ts
import { query, mutation } from "./_generated/server";
import { v, ConvexError } from "convex/values";
import { getAuthUserId } from "@convex-dev/auth/server";

async function requireUserId(ctx: { auth: any; db: any }) {
  const userId = await getAuthUserId(ctx as any);
  if (userId === null) throw new ConvexError("Not authenticated");
  return userId;
}

export const list = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    return await ctx.db
      .query("meetings")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .order("desc")
      .collect();
  },
});

export const create = mutation({
  args: { title: v.string(), notes: v.optional(v.string()) },
  handler: async (ctx, { title, notes }) => {
    const userId = await requireUserId(ctx);
    const clean = title.trim();
    if (clean.length === 0) throw new ConvexError("Title required");
    return await ctx.db.insert("meetings", {
      userId,
      title: clean,
      notes: notes?.trim() || undefined,
      createdAt: Date.now(),
      status: "note",
    });
  },
});

export const remove = mutation({
  args: { id: v.id("meetings") },
  handler: async (ctx, { id }) => {
    const userId = await requireUserId(ctx);
    const row = await ctx.db.get(id);
    if (row === null || row.userId !== userId) {
      throw new ConvexError("Not found"); // don't reveal others' rows
    }
    await ctx.db.delete(id);
  },
});
```

- [ ] **Step 5: Run to verify GREEN**

Run: `cd apps/web && npm run test -- meetings`
Expected: PASS (4 tests). If `_generated` is absent, run `npx convex codegen` (or the Task-5 deploy) first, then re-run.

- [ ] **Step 6: Commit**

```bash
git add apps/web/convex/schema.ts apps/web/convex/meetings.ts apps/web/convex/meetings.test.ts
git commit -m "feat(web): identity-scoped meetings schema + list/create/remove + convex-test authz tests"
```

---

## Task 3: Convex Auth wiring + provider + AuthForm + auth-state App switch

**Files:**
- Create: `apps/web/convex/{auth.ts, http.ts, auth.config.ts}`, `apps/web/src/components/AuthForm.tsx`, `apps/web/src/test/AuthForm.test.tsx`
- Modify: `apps/web/src/main.tsx`, `apps/web/src/App.tsx`

**Interfaces:**
- Consumes: `ConvexAuthProvider`, `useAuthActions` from `@convex-dev/auth/react`; `<Authenticated>/<Unauthenticated>/<AuthLoading>` from `convex/react`.
- Produces: `AuthForm` (email+password, sign-in/sign-up toggle); `App` renders AuthForm when unauthenticated and a placeholder "signed in" panel when authenticated (Dashboard lands in Task 4).

- [ ] **Step 1: Backend auth files**

`apps/web/convex/auth.ts`:
```ts
import { Password } from "@convex-dev/auth/providers/Password";
import { convexAuth } from "@convex-dev/auth/server";

export const { auth, signIn, signOut, store, isAuthenticated } = convexAuth({
  providers: [Password],
});
```
`apps/web/convex/http.ts`:
```ts
import { httpRouter } from "convex/server";
import { auth } from "./auth";

const http = httpRouter();
auth.addHttpRoutes(http);
export default http;
```
`apps/web/convex/auth.config.ts`:
```ts
export default {
  providers: [
    { domain: process.env.CONVEX_SITE_URL, applicationID: "convex" },
  ],
};
```
(The user's `npx @convex-dev/auth` provisions `JWT_PRIVATE_KEY`/`JWKS` and `SITE_URL`/`CONVEX_SITE_URL` env vars on the deployment; if it rewrites these files, keep its output.)

- [ ] **Step 2: Provider in main.tsx**

`apps/web/src/main.tsx`:
```tsx
import React from "react";
import ReactDOM from "react-dom/client";
import { ConvexReactClient } from "convex/react";
import { ConvexAuthProvider } from "@convex-dev/auth/react";
import App from "./App";
import "./index.css";

const convex = new ConvexReactClient(import.meta.env.VITE_CONVEX_URL as string);

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <ConvexAuthProvider client={convex}>
      <App />
    </ConvexAuthProvider>
  </React.StrictMode>,
);
```

- [ ] **Step 3: Write the failing AuthForm test**

`apps/web/src/test/AuthForm.test.tsx`:
```tsx
import { render, screen, fireEvent } from "@testing-library/react";
import { vi } from "vitest";
import AuthForm from "../components/AuthForm";

const signIn = vi.fn(() => Promise.resolve());
vi.mock("@convex-dev/auth/react", () => ({
  useAuthActions: () => ({ signIn, signOut: vi.fn() }),
}));

test("submits email/password with the signIn flow", async () => {
  render(<AuthForm />);
  fireEvent.change(screen.getByLabelText(/email/i), { target: { value: "a@b.com" } });
  fireEvent.change(screen.getByLabelText(/password/i), { target: { value: "pw123456" } });
  fireEvent.click(screen.getByRole("button", { name: /sign in/i }));
  expect(signIn).toHaveBeenCalledWith("password", {
    email: "a@b.com", password: "pw123456", flow: "signIn",
  });
});
```

- [ ] **Step 4: Run to verify it fails**

Run: `cd apps/web && npm run test -- AuthForm`
Expected: FAIL — `AuthForm` not found.

- [ ] **Step 5: Implement AuthForm**

`apps/web/src/components/AuthForm.tsx`:
```tsx
import { useState } from "react";
import { useAuthActions } from "@convex-dev/auth/react";

export default function AuthForm() {
  const { signIn } = useAuthActions();
  const [flow, setFlow] = useState<"signIn" | "signUp">("signIn");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true); setError(null);
    try {
      await signIn("password", { email, password, flow });
    } catch (err) {
      setError(flow === "signIn" ? "Could not sign in." : "Could not sign up.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="min-h-screen grid place-items-center p-6">
      <form onSubmit={submit}
        className="w-full max-w-sm rounded-xl border border-outline bg-surface p-8 space-y-4">
        <h1 className="text-2xl font-bold text-primary">Privoice</h1>
        <label className="block text-sm">Email
          <input aria-label="Email" type="email" required value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="mt-1 w-full rounded-lg border border-outline px-3 py-2" />
        </label>
        <label className="block text-sm">Password
          <input aria-label="Password" type="password" required value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="mt-1 w-full rounded-lg border border-outline px-3 py-2" />
        </label>
        {error && <p className="text-sm text-red-600">{error}</p>}
        <button type="submit" disabled={busy}
          className="w-full rounded-lg bg-primary py-2 font-semibold text-white disabled:opacity-60">
          {flow === "signIn" ? "Sign in" : "Sign up"}
        </button>
        <button type="button" onClick={() => setFlow(flow === "signIn" ? "signUp" : "signIn")}
          className="w-full text-sm text-primary">
          {flow === "signIn" ? "Need an account? Sign up" : "Have an account? Sign in"}
        </button>
      </form>
    </main>
  );
}
```

- [ ] **Step 6: App auth-state switch**

`apps/web/src/App.tsx`:
```tsx
import { Authenticated, Unauthenticated, AuthLoading } from "convex/react";
import { useAuthActions } from "@convex-dev/auth/react";
import AuthForm from "./components/AuthForm";

export default function App() {
  const { signOut } = useAuthActions();
  return (
    <>
      <AuthLoading>
        <main className="min-h-screen grid place-items-center">Loading…</main>
      </AuthLoading>
      <Unauthenticated>
        <AuthForm />
      </Unauthenticated>
      <Authenticated>
        {/* Dashboard replaces this in Task 4 */}
        <main className="min-h-screen p-6">
          <button onClick={() => signOut()} className="text-primary">Sign out</button>
          <p className="mt-4 text-on-surface-variant">Signed in.</p>
        </main>
      </Authenticated>
    </>
  );
}
```

- [ ] **Step 7: Verify GREEN + build**

Run:
```bash
cd apps/web && npm run test -- AuthForm    # passes
npx tsc --noEmit                            # clean
npm run build                               # succeeds
```

- [ ] **Step 8: Commit**

```bash
git add apps/web/convex/auth.ts apps/web/convex/http.ts apps/web/convex/auth.config.ts \
  apps/web/src/main.tsx apps/web/src/App.tsx apps/web/src/components/AuthForm.tsx \
  apps/web/src/test/AuthForm.test.tsx
git commit -m "feat(web): Convex Auth (Password) — provider, http routes, AuthForm, auth-state switch"
```

---

## Task 4: Dashboard — live meetings list + create + delete

**Files:**
- Create: `apps/web/src/components/Dashboard.tsx`, `apps/web/src/test/Dashboard.test.tsx`
- Modify: `apps/web/src/App.tsx` (render `<Dashboard/>` in the `<Authenticated>` slot)

**Interfaces:**
- Consumes: `useQuery(api.meetings.list)`, `useMutation(api.meetings.create|remove)`, `useAuthActions().signOut`.
- Produces: the authenticated dashboard UI.

- [ ] **Step 1: Write the failing Dashboard test (mocked Convex)**

`apps/web/src/test/Dashboard.test.tsx`:
```tsx
import { render, screen, fireEvent } from "@testing-library/react";
import { vi } from "vitest";
import Dashboard from "../components/Dashboard";

const create = vi.fn(() => Promise.resolve());
vi.mock("convex/react", () => ({
  useQuery: () => [{ _id: "1", title: "Existing", createdAt: 0, status: "note" }],
  useMutation: () => create,
}));
vi.mock("@convex-dev/auth/react", () => ({ useAuthActions: () => ({ signOut: vi.fn() }) }));

test("lists meetings and creates a new one", async () => {
  render(<Dashboard />);
  expect(screen.getByText("Existing")).toBeInTheDocument();
  fireEvent.change(screen.getByLabelText(/new meeting title/i), { target: { value: "Standup" } });
  fireEvent.click(screen.getByRole("button", { name: /add/i }));
  expect(create).toHaveBeenCalledWith({ title: "Standup", notes: undefined });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/web && npm run test -- Dashboard`
Expected: FAIL — `Dashboard` not found.

- [ ] **Step 3: Implement Dashboard**

`apps/web/src/components/Dashboard.tsx`:
```tsx
import { useState } from "react";
import { useQuery, useMutation } from "convex/react";
import { useAuthActions } from "@convex-dev/auth/react";
import { api } from "../../convex/_generated/api";

export default function Dashboard() {
  const { signOut } = useAuthActions();
  const meetings = useQuery(api.meetings.list) ?? [];
  const create = useMutation(api.meetings.create);
  const remove = useMutation(api.meetings.remove);
  const [title, setTitle] = useState("");

  async function add(e: React.FormEvent) {
    e.preventDefault();
    const t = title.trim();
    if (!t) return;
    await create({ title: t, notes: undefined });
    setTitle("");
  }

  return (
    <main className="mx-auto max-w-2xl p-6">
      <header className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-primary">Your meetings</h1>
        <button onClick={() => signOut()} className="text-sm text-primary">Sign out</button>
      </header>

      <form onSubmit={add} className="mt-6 flex gap-2">
        <input aria-label="New meeting title" value={title}
          onChange={(e) => setTitle(e.target.value)} placeholder="New meeting title"
          className="flex-1 rounded-lg border border-outline px-3 py-2" />
        <button type="submit"
          className="rounded-lg bg-primary px-4 py-2 font-semibold text-white">Add</button>
      </form>

      <ul className="mt-6 space-y-2">
        {meetings.map((m: any) => (
          <li key={m._id}
            className="flex items-center justify-between rounded-xl border border-outline bg-surface p-4">
            <span>{m.title}</span>
            <button onClick={() => remove({ id: m._id })}
              className="text-sm text-on-surface-variant hover:text-red-600">Delete</button>
          </li>
        ))}
        {meetings.length === 0 && (
          <li className="text-on-surface-variant">No meetings yet — add one above.</li>
        )}
      </ul>
    </main>
  );
}
```

- [ ] **Step 4: Wire into App**

In `apps/web/src/App.tsx`, replace the `<Authenticated>` placeholder body with `<Dashboard />` (import it; drop the now-unused inline `signOut`/placeholder).

- [ ] **Step 5: Verify GREEN + build**

Run:
```bash
cd apps/web && npm run test        # all component tests pass
npx tsc --noEmit                    # clean
npm run build                       # succeeds
```

- [ ] **Step 6: Commit**

```bash
git add apps/web/src/components/Dashboard.tsx apps/web/src/test/Dashboard.test.tsx apps/web/src/App.tsx
git commit -m "feat(web): dashboard — live meetings list + create + delete"
```

---

## Task 5: Account-bound deploy, live e2e, security review, STATUS, finish

**Files:** Modify `STATUS.md`.

- [ ] **Step 1: Hand the user the account-bound commands** (they run; agent does not handle secrets)

```bash
cd apps/web
echo 'VITE_CONVEX_URL=https://colorless-mammoth-659.convex.cloud' > .env.local
npm install
npx @convex-dev/auth      # provisions JWT/JWKS + SITE_URL env vars on the deployment
npx convex dev            # codegen (_generated) + push functions (leave running, or --once)
```

- [ ] **Step 2: Run the backend authz tests against generated types**

Once `_generated/` exists:
```bash
cd apps/web && npm run test -- meetings
```
Expected: PASS (4 authz tests). If `getAuthUserId` can't be driven under convex-test with the crafted identity, adjust the identity subject format to match the installed `@convex-dev/auth` version and re-run; report the resolution.

- [ ] **Step 3: Live e2e (user, in browser)** — `npm run dev`, then:
- sign up (new email/password) → lands on the dashboard;
- add a meeting → appears live; reload → still there;
- delete → disappears;
- sign out → back to AuthForm;
- sign up a **second** account → sees **none** of the first account's meetings.
Report pass/fail per step; do not claim verified until the user confirms.

- [ ] **Step 4: Security review**

Run `/security-review` on the O1 diff. Confirm: no secret committed (`.env.local`/keys gitignored), every `meetings` function is identity-gated, `remove` refuses cross-user rows, no unauthenticated data path, no secret logged. Fix any finding before merge.

- [ ] **Step 5: STATUS.md**

Flip **O1** to ✅ (code-complete; add *verified* after Step 3 confirms). Note the deployment, the email/password-only scope, and OAuth as the next O-slice fast-follow. Update the "What's next" pointer to the next web slice (web meeting UI / audio-upload, or O2 billing per priority). Commit:
```bash
git add STATUS.md && git commit -m "docs(status): O1 web scaffold + auth code-complete"
```

- [ ] **Step 6: Finish the branch**

Use `superpowers:finishing-a-development-branch` to merge `feat/o1-web-scaffold` into `main` (`--no-ff`) once tests are green and (per convention) e2e-verified.

---

## Self-Review

**Spec coverage:** auth provider (Convex Auth Password) → T3 ✅ · email/password only → T3 ✅ · identity-scoped meetings CRUD → T2 ✅ · repo layout `convex/` in `apps/web` → T1/T2 ✅ · React+Vite+Tailwind calm-teal → T1 ✅ · dashboard list/create/delete → T4 ✅ · security section (identity-gated, no secrets, isolation tested, /security-review) → Global Constraints + T2 + T5 ✅ · account-bound steps → T5 ✅ · out-of-scope respected (no OAuth/audio/AI/billing) ✅.

**Placeholder scan:** no TBD/"handle errors" — every code step has full code. The one deferred detail is the exact `getAuthUserId` identity format under convex-test, which is called out with a concrete pattern + a fallback instruction (version-dependent) rather than left vague.

**Type consistency:** `api.meetings.{list,create,remove}` signatures match across T2 (definition), T4 (UI calls: `create({title, notes})`, `remove({id})`), and the tests. `requireUserId(ctx)` used by all three functions. `VITE_CONVEX_URL`, `ConvexAuthProvider`, `useAuthActions().signIn("password",{email,password,flow})` consistent T3↔T5.

**Dependency note:** T2's test *run* and T5 depend on the account-bound `convex dev` producing `_generated/`. The code (T1–T4) is authored and committed independently; only the RED/GREEN execution of `meetings.test.ts` may wait for the deploy gate. Flagged in T2's depends-on note.
