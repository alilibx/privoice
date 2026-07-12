# Web Redesign — Privoice Cloud (shadcn SaaS shell + agentic chat UX + model selection)

**Date:** 2026-07-12
**Status:** Approved design — ready for implementation plan
**Scope:** `apps/web` only (React + Vite SPA on Convex). No mobile/Flutter changes.

## Goal

Redesign the Privoice Cloud web app into a proper SaaS product using shadcn/ui,
with a real app shell, feature-based structure, light/dark/system theming, and
two chat UX upgrades — a visible **agent activity trace** (tool-calling) and an
in-chat **document thumbnail** for uploads. Add a **Settings** page with a
**model picker + cost/quality comparison** so the user can choose the chat model
(cost-aware, curated for agentic tool-calling and RAG).

This is a presentation-layer restructure plus three additive features. Existing
Convex backend logic (auth, meetings CRUD, document ingestion, RAG, agentic
chat) is preserved; the only backend additions are model selection
(`userSettings` + `settings.ts`) and reading that setting in `sendMessage`.

## Non-goals (explicitly out of scope)

- Server-side meeting audio upload / STT (separate planned web slice).
- Billing / BYOK / OAuth (O2 fast-follow).
- Real rendered PDF page previews (thumbnails are file-type cards, not page images).
- Changing RAG/ingestion behavior or the tools' logic.
- Per-chat or per-thread model override — model is a single per-user default.

## Approach

Vendor the specific shadcn/ui primitives we need (MIT copy-paste components — no
CLI/network dependency, no bloat), wire up `cn()`, the `@/` path alias, and
CSS-variable theming mapped from the mobile app's hand-tuned light/dark scheme.
Restructure into a feature-based layout with a collapsible sidebar shell and URL
routing. Rejected alternatives: `shadcn` CLI init (fragile against our existing
hex-based Tailwind config; overwrites `index.css`/config; needs network), and
restyle-in-place (fails the "proper structure / SaaS" requirement).

## Theming — single source of truth with mobile

Map `apps/mobile/lib/theme.dart`'s `ColorScheme` into shadcn's CSS-variable token
contract so web matches the product exactly in both themes.

- `darkMode: "class"` in `tailwind.config`.
- `index.css` defines two token blocks: `:root` (light) and `.dark` (dark),
  each populating shadcn tokens (`--background`, `--foreground`, `--card`,
  `--card-foreground`, `--popover`, `--primary`, `--primary-foreground`,
  `--secondary`, `--muted`, `--muted-foreground`, `--accent`, `--border`,
  `--input`, `--ring`, `--destructive`, `--radius`, etc.).
- Values sourced from the mobile scheme:
  - **Light:** primary `#12708D`, page-bg `#EEF3F6`, surface `#FFFFFF`,
    on-surface `#0F1D24`, on-surface-variant `#5C6E77`, outline `#DDE7EC`,
    error `#DB554D`, surface containers `#F6F9FB`/`#F1F6F8`/`#EAF1F4`.
  - **Dark:** primary `#4FB4D1`, page-bg `#0A1216`, surface `#111C22`,
    on-surface `#E9F0F3`, on-surface-variant `#93A6AF`, outline `#3A4C55`,
    error `#EF736B`, surface containers `#141F26`/`#16232A`/`#1B2A32`.
  - `--radius` ~ `0.9rem` to reflect the mobile 18px card radius.
- Tailwind `theme.extend.colors` reference the CSS vars (shadcn convention), so
  utilities like `bg-primary`, `text-muted-foreground`, `border-border` work.
- `ThemeProvider` (`src/lib/theme-provider.tsx`): light/dark/system, persisted to
  `localStorage`, resolves `system` via `prefers-color-scheme` and toggles the
  `.dark` class on `<html>`. Replaces the current `color-scheme: light` pin.

## Folder structure (the "proper structure")

```
apps/web/src/
  components/ui/         # vendored shadcn primitives:
                         #   button, input, textarea, card, dialog,
                         #   dropdown-menu, avatar, badge, tooltip, scroll-area,
                         #   separator, skeleton, radio-group, table, sonner (toast)
  components/layout/     # AppShell, Sidebar, Topbar, ThemeToggle, UserMenu
  features/
    auth/                # AuthForm
    chat/                # Chat, ThreadList, MessageBubble, ToolTrace,
                         #   AttachmentCard, Composer
    meetings/            # MeetingsList, MeetingCard, NewMeetingDialog
    documents/           # DocumentsList, DocumentCard, UploadDropzone, StatusBadge
    settings/            # SettingsPage, AppearanceSection, ModelSection,
                         #   ModelComparison
  lib/                   # utils.ts (cn), theme-provider.tsx, file-icons.ts,
                         #   models.ts (curated allowlist + ratings)
  App.tsx  main.tsx  index.css
```

- Add `react-router-dom`. Routes: `/chat`, `/meetings`, `/documents`,
  `/settings`; index redirects to `/chat`. Bookmarkable, browser-back works.
  `AppShell` wraps the authenticated routes; unauthenticated → `AuthForm`.
- New deps: `react-router-dom`, `class-variance-authority`, `clsx`,
  `tailwind-merge`, `tailwindcss-animate`, `lucide-react` (icons),
  `@radix-ui/*` (per vendored component), `sonner`.
- `@/` alias → `src/` in both `vite.config.ts` (`resolve.alias`) and
  `tsconfig.json` (`compilerOptions.paths`). Add `components.json` for shadcn
  provenance/config.

## App shell

- **Sidebar** (`components/layout/Sidebar.tsx`): Privoice wordmark; nav items
  (Chat, Meetings, Documents, Settings) with `lucide-react` icons + active state
  from the router; a collapse toggle whose state persists to `localStorage`.
  Collapsed → icon-only rail with tooltips.
- **Topbar** (`components/layout/Topbar.tsx`): current page title, `ThemeToggle`,
  `UserMenu` (Avatar → dropdown with the user's email + Sign out via
  `useAuthActions().signOut`).
- **Main**: routed content area, scrollable, max-width container per page.
- **Auth** redesigned as a centered shadcn `Card` using the same tokens.
- Responsive: on narrow viewports the sidebar collapses to the icon rail (a full
  mobile drawer is a nice-to-have, not required for this slice).

## Chat redesign (two feature adds live here)

Data source unchanged: `useUIMessages(api.chat.listMessages, …, { stream: true })`
returns messages with `role`, `text`, `status`, and `parts` (which already carry
`tool-*` parts with `state`). `useSmoothText` streaming preserved.

### Agent activity trace (`ToolTrace`)

Replaces the current one-line "Searching your documents…" italic.

- For each assistant message, derive its tool steps from
  `parts.filter(p => p.type.startsWith("tool-"))`.
- Render a compact, collapsible timeline **above** the assistant's answer text:
  - Friendly label per tool: `tool-searchDocuments` → "Searched your documents",
    `tool-searchMeetings` → "Searched your meetings".
  - The query argument (from the part's input/args), shown inline.
  - Live state: `input-streaming`/`input-available` → running spinner;
    `output-available` → done check; `output-error` → error style.
  - Expanding a step reveals the result summary (the tool's returned text,
    truncated with a "show more").
- Multiple steps stack in order. When no tool ran, no trace renders.
- Keep the existing "hide empty tool-only assistant turn" guard so intermediate
  tool-call turns don't render as empty bubbles.
- Read the part shapes from `@convex-dev/agent`'s UIMessage `parts` at
  implementation time; the component stays defensive about optional fields.

### Document thumbnail (`AttachmentCard`)

Attaching a file in the composer uploads it (existing `generateUploadUrl` +
`documents.create`) and shows an attachment card in the chat.

- Card contents: file-type icon (color-coded by kind — PDF / Word / Excel /
  txt / md, via `lib/file-icons.ts`), filename (truncated), human-readable size,
  and live parse status reused from the document's `status`
  (`parsing` → "Parsing…", `ready` → "Ready", `failed` → "Failed").
- Rendered as the user's attachment in the message stream. Status updates live
  via the reactive `documents.list`/doc query.
- No pdf.js / rendered page image — file-type card only (per scope).

### Composer

Redesigned with shadcn: auto-grow `Textarea`, an attach `Button` with a
`lucide` paperclip icon (busy state), and a send `Button` (disabled when empty
or sending). Enter-to-send / Shift+Enter-newline preserved. Optimistic echo of
sent user messages preserved.

## Meetings / Documents / Auth (redesign, same behavior)

- **Meetings** (`features/meetings`): card list/grid; "New meeting" via a shadcn
  `Dialog`; keep `meetings.create` / `meetings.remove`. Empty state.
- **Documents** (`features/documents`): drag-and-drop `UploadDropzone` (plus
  click-to-upload), document cards with `StatusBadge`
  (Parsing… / Ready · N chunks / Failed with error tooltip); keep
  `generateUploadUrl` / `documents.create` / `documents.remove`. Empty state.
- **Auth** (`features/auth`): shadcn `Card` + `Input`s + `Button`; same
  `signIn("password", …)` flow, sign-in/sign-up toggle, and error surfacing.

## Settings + model selection (new)

### Route

`/settings` in the sidebar. Two sections:

- **Appearance** — light / dark / system theme control (drives `ThemeProvider`).
- **Model** — comparison table + active-model selector.

### Curated allowlist (`lib/models.ts`)

Server- and client-shared curated list of OpenRouter model slugs, each with our
own qualitative ratings for **Tool-calling** and **RAG** (e.g. Good / Strong /
Best). Exact slugs validated against the live `/models` list; unknown slugs are
simply omitted from the UI.

- `openai/gpt-4o-mini` — budget baseline (current default).
- `anthropic/claude-haiku-4.5` — cheap/mid, strong agentic tool-calling.
- `anthropic/claude-sonnet-4.5` — mid-premium, top-tier agentic + RAG.
- `openai/gpt-4o` — frontier GPT option.
- `google/gemini-2.0-flash` — cheap/fast breadth.

The **default** model when a user has no saved setting is `openai/gpt-4o-mini`.

### Backend

- **Schema** — new `userSettings` table:
  `{ userId: Id<"users">, modelId: string, updatedAt: number }`, index
  `by_user`.
- **`convex/settings.ts`:**
  - `getSettings` (query) — returns the caller's `{ modelId }`, defaulting to
    `openai/gpt-4o-mini` when unset.
  - `setModel` (mutation) — **validates `modelId` against the server-side
    allowlist** (from `lib/models.ts`, imported server-side); rejects anything
    else with a `ConvexError`. Upserts the user's row.
  - `listModels` (action) — fetches OpenRouter `GET /models` server-side
    (using `OPENROUTER_API_KEY`), filters to the allowlist, merges live pricing
    (input/output per 1M tokens) with our curated ratings, returns
    `Array<{ id, name, promptPrice, completionPrice, toolRating, ragRating }>`.
    Fail-soft: on fetch error, return the curated entries without live pricing
    rather than erroring the page.
- **`sendMessage`** — resolve the model **server-side**: read the caller's
  `userSettings.modelId`, validate against the allowlist (fail-closed to the
  default), and pass `model: openrouter.chat(modelId)` into
  `thread.streamText({ prompt, model }, …)`. The client never supplies a model
  id to generation.

### Client

- `ModelComparison` renders a shadcn `Table` (or responsive card list) of the
  `listModels` result: name, cost, Tool-calling badge, RAG badge, and a
  `RadioGroup`/select bound to the current `getSettings().modelId`; choosing one
  calls `setModel`. Loading → `Skeleton`s.
- Chat header shows the active model as a small read-only label linking to
  `/settings`.

### Security invariant

Per the project's security-first standard: the generation model is resolved and
validated **server-side** from the user's persisted setting against a fixed
allowlist; the client cannot inject an arbitrary model id into generation.
`OPENROUTER_API_KEY` remains server-only (read from `process.env`, never sent to
or logged for the client). Model selection is per-user and ownership-scoped like
every other user-owned row.

## Testing (per "tests runnable from the start")

- Update the existing Vitest suites to the new component locations/queries and
  keep them green: `AuthForm`, `Chat`, `Dashboard`→meetings, `Documents`, smoke.
- New component tests:
  - `ToolTrace` — renders labeled steps + states from a `parts` fixture; renders
    nothing when there are no tool parts.
  - `AttachmentCard` — correct icon + status label per file kind.
  - `ModelComparison` — renders rows from a `listModels` fixture; selecting a row
    calls `setModel`.
- New backend test `convex/settings.test.ts` (convex-test):
  - `getSettings` returns the default when unset.
  - `setModel` persists an allowlisted id and **rejects a non-allowlisted id**.
- `melos run analyze` clean; `apps/web` `tsc -b && vite build` succeeds;
  `vitest run` green. Wire remains within the existing web CI.

## Rollout / structure of the work

Implementation naturally splits into slices (exact plan produced by
writing-plans):

1. **Foundation** — deps, `@/` alias, `cn`, shadcn tokens from mobile scheme,
   `ThemeProvider`, vendored `ui/` primitives. (Build stays green.)
2. **App shell + routing** — `AppShell`/`Sidebar`/`Topbar`, react-router,
   redesigned `AuthForm`. Move existing screens behind the shell unchanged
   visually first.
3. **Chat redesign** — `ToolTrace`, `AttachmentCard`, `Composer`.
4. **Meetings + Documents redesign.**
5. **Settings + model selection** — schema, `settings.ts`, `sendMessage` model
   resolution, `ModelComparison`, chat header label.
6. **Tests + analyze/build green + STATUS.md update.**

## STATUS.md

On completion, add this as a completed web slice (e.g. **C3 — web redesign**)
under the "Privoice Cloud" workstream, marked ✅ only after `analyze`/build/tests
pass and it has been run in the browser.
