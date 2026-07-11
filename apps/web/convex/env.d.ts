// Convex's server runtime exposes `process.env` for deployment env vars
// (e.g. CONVEX_SITE_URL used by auth.config.ts), but this project has no
// @types/node dependency (it would leak Node ambient globals into the
// browser-side src/ code sharing this tsconfig). Declare just the shape we
// use, scoped to the convex/ directory's needs.
declare const process: { env: Record<string, string | undefined> };
