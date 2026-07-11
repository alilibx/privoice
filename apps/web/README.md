# privoice-web

Web client for Privoice — Vite + React + TypeScript + Tailwind, backed by Convex. Fully
independent npm project (not a melos package); lives at `apps/web` alongside the Flutter
mobile app in this monorepo.

## Install

```bash
cd apps/web
npm install
```

## Dev

```bash
npm run dev       # Vite dev server
npm run test      # vitest run (smoke test etc.)
npx tsc --noEmit  # type-check only
npm run build     # tsc -b && vite build → dist/
npm run preview   # serve the production build locally
```

## Convex setup (account-bound — run once per developer/environment)

These commands need a Convex account and will prompt for auth / project selection.
Run them in order the first time you set up this app against a real Convex deployment:

```bash
npm install                # installs the convex + @convex-dev/auth CLIs/libs (already done above)
npx @convex-dev/auth       # scaffolds Convex Auth config (auth.config.ts, providers, etc.)
npx convex dev             # logs in, links/creates a Convex deployment, starts the dev backend
```

`npx convex dev` prints the deployment URL. Put it in `apps/web/.env.local` (never committed):

```
VITE_CONVEX_URL=https://<your-deployment>.convex.cloud
```

`.env.local`, `node_modules/`, `dist/`, and `convex/_generated/` are all gitignored — never
commit secrets or generated Convex code.

## Status

Task 1 (this scaffold) ships a static placeholder `App.tsx` with the calm-teal palette
(mirrored from `apps/mobile/lib/theme.dart`) and no Convex wiring yet. Convex schema,
functions, auth, and the real dashboard land in later O1 tasks — see `STATUS.md` at the
repo root.
