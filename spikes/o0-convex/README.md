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

## Findings

_(to fill in after running: which client won — `convex_flutter` vs raw HTTP —
auth notes, file-storage notes, and the Go/No-Go recommendation for O1.)_
