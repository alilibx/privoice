# O0 spike — Flutter ↔ Convex (throwaway)

**Goal:** de-risk the mobile↔Convex seam before committing to O1 (real backend).
Prove: (1) call a Convex **query**/**mutation** from Flutter via `convex_flutter`,
(2) the plain **HTTP-action** transport works from Dart, (3) an **auth** token
round-trips, (4) **file storage** upload→read-back works.

Deployment: `colorless-mammoth-659` (`https://colorless-mammoth-659.convex.cloud`).
> Convex serves **httpActions on `.convex.site`**, and the client API/WebSocket on
> **`.convex.cloud`**. The Dart smoke test hits `.convex.site`.

## What's here

| File | Proves |
|---|---|
| `convex/ping.ts` (`query`) | typed read via the Convex client |
| `convex/echo.ts` (`mutation`) | args + return marshalling on writes |
| `convex/http.ts` (`GET /ping`, `POST /echo`) | plain-HTTP transport (headless-testable) |
| `convex/files.ts` (`generateUploadUrl` + `getUrl`) | audio-upload path for web/online tier |
| `dart_smoke/` | headless Dart client for the HTTP-action path |

## Deploy (your step — account-bound)

The agent does not create/link Convex projects or handle deploy-key secrets.
From this folder, with your logged-in Convex CLI:

```bash
cd spikes/o0-convex
npm install
npx convex dev            # links this folder to your existing project/deployment, runs codegen, watches
# ...or one-shot deploy without watching:
npx convex dev --once
```

When prompted, choose the **existing** `colorless-mammoth-659` deployment (do
NOT create a new project). This generates `convex/_generated/` and pushes the
functions.

## Verify the HTTP-action path (headless, no device)

```bash
cd spikes/o0-convex/dart_smoke
dart pub get
dart run bin/smoke.dart https://colorless-mammoth-659.convex.site
# expect: ✅ GET /ping, ✅ POST /echo
```

## Still to wire (needs a Flutter runtime / device)

- `convex_flutter` client calling `ping`/`echo` (query/mutation over WebSocket).
- Convex Auth token flow from Flutter + one authenticated call.
- File upload from Flutter using `generateUploadUrl` → `getUrl`.

These land as a throwaway Flutter target once the HTTP path is confirmed.

## Findings (2026-07-12) — **GO**

- **HTTP-action transport from Dart: ✅ proven headlessly.** `dart run bin/smoke.dart
  https://colorless-mammoth-659.convex.site` → `✅ GET /ping (200)`, `✅ POST /echo (200, len=15)`.
  So the plain-HTTP fallback path works from Dart with zero native deps.
- **`convex_flutter` viability: ✅ confirmed by evaluation** (not yet run on device).
  v3.0.1, verified publisher (jkuldev.com), supports **Android/iOS/web/desktop**;
  Rust FFI on native, pure Dart on web. API: `ConvexClient.initialize(ConvexConfig(deploymentUrl, clientId))`,
  `client.subscribe(name:'file:fn', args, onUpdate)`, `client.mutation(name, args)`,
  `client.setAuth(token)` / `setAuthWithRefresh(fetchToken)`. It's a **community** package
  (not first-party Convex) — acceptable, but pin the version and keep the HTTP-action
  fallback in mind.
- **Key reframing for the web-first plan:** the **web app is Next.js/React**, which uses
  **Convex's official `convex/react` client** — mature, first-party, essentially zero
  integration risk. `convex_flutter` only matters for the **mobile online tier (O5)** and
  desktop. So the Flutter↔Convex risk is **off the web critical path**.

### Go/No-Go for O1: **GO**
Proceed to O1 (Convex backend + shared auth + Next.js web scaffold) using the official
React client. **Deferred (folded into O5, mobile online tier):** a throwaway on-device
`convex_flutter` run proving native lib load + WebSocket connect + auth token + file
upload on a real Android build. Not blocking the web work.
