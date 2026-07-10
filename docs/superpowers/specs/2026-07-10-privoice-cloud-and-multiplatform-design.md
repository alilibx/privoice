# Privoice Cloud + Multi-platform — Design

**Date:** 2026-07-10
**Status:** Draft for review. Own sub-project; the on-device roadmap (S4/S5/S7…) continues in parallel.

## 1. Vision

Privoice becomes a multi-platform suite from one Flutter codebase, plus an opt-in online layer:

- **On-device (default, free, private):** Android ✅, iOS (later), **macOS/Windows/Linux (new)** — record → transcribe → summarize → chat, fully offline.
- **Online tier (opt-in, off by default):** a **web app** and an **online mode in the apps**, with **shared accounts**, **subscription** to hosted AI models, and **BYOK** as a no-subscription alternative.

Privacy invariant unchanged: nothing leaves the device unless the user explicitly turns on an online mode.

## 2. Stack (decided)

| Concern | Choice |
|---|---|
| Backend | **Convex** — auth, reactive DB, server functions (queries/mutations/actions), file storage |
| Web | **Next.js / React** (dedicated), using the Convex React client |
| Billing | **RevenueCat** — App Store + Play + web (Stripe); entitlements synced to Convex via webhook |
| Online models | **OpenRouter** — one API for many models |
| Mobile/desktop | **Flutter** (existing codebase) |

## 3. Architecture

```
Flutter apps (mobile + desktop) ─┐          ┌── OpenRouter
                                 ├─ Convex ──┤   (our key = subscription; user key = BYOK)
Next.js web ─────────────────────┘  • Auth (shared identity)
                                     • DB: users, entitlements, documents, chatThreads, messages
                                     • Storage: uploaded PDFs/docx
                                     • Actions: aiProxy, parseDocument (Node: pdf-parse/mammoth)
                                     • httpAction: RevenueCat webhook, mobile REST surface
```

### 3.1 Auth (shared accounts)
Convex Auth (email + Google + Apple). Web uses the Convex React client directly. Mobile authenticates against Convex and stores the session token, calling Convex **httpActions** (Convex has no first-class Dart client — see Risk R1).

### 3.2 Subscription vs BYOK (the online tier, two modes)
- **Subscription:** RevenueCat entitlement → mirrored into Convex (`users.entitlement`) via webhook. The `aiProxy` action checks entitlement, then calls OpenRouter with **our** key, enforcing per-plan usage limits (tokens/minutes) tracked in Convex.
- **BYOK (no subscription):** user stores their OpenRouter key (encrypted at rest in Convex, or kept client-side and sent per request). `aiProxy` uses the user's key. Their cost; we only meter for UX.
- Neither is required for on-device use.

### 3.3 Online AI chat with documents (web-first, O4)
Upload doc → Convex file storage → `parseDocument` action (pdf-parse / mammoth / plain) → chunk → store chunks → chat grounds on transcript + doc chunks via retrieval → `aiProxy` → OpenRouter. Same `AiEngine` *interface* concept as on-device, different implementation (`OnlineAiEngine` calling Convex).

## 4. Multi-platform (Flutter)

Reuses `audio` / `stt` / `ai` packages unchanged. Platform seams:
- **Storage:** `sqflite` on mobile; **`sqflite_common_ffi`** on desktop (init `databaseFactory` at startup).
- **Paths:** a `PlatformPaths` abstraction (built in **S5**) resolves model + data dirs per OS (Android files dir, desktop app-support dir, etc.). Removes the Android-only flat-push hack.
- **Native libs:** sherpa-onnx + fllama ship desktop binaries; verify bundling per OS.
- **Desktop UX:** window sizing, menu bar, keyboard; macOS first (testable here), then Windows/Linux.

## 5. Security & privacy

- Online tier **off by default**, clearly labelled per surface; on-device remains the default path.
- BYOK keys: never logged; encrypted at rest or client-only. Card/payment entry handled entirely by RevenueCat/Stripe UI — never by us.
- The `aiProxy` never persists audio/transcript/doc content beyond what the feature needs; retention policy documented. (The future self-hosted zero-retention/GCC tier is a separate later phase.)
- Convex functions authorize every call by identity + entitlement.

## 6. Decomposition

**Online Platform:** O0 spike → O1 backend+auth+web scaffold → O2 subscription+BYOK → O3 AI proxy → O4 web chat-with-docs → O5 mobile online client.
**Desktop:** D0 enable+verify → D1 sqflite-ffi + PlatformPaths → D2 UX + Windows/Linux.
(Full list tracked in STATUS.md.)

## 7. Risks

- **R1 — Flutter ↔ Convex:** no official Dart SDK. Mitigation: **O0 spike** validates HTTP-action + token flow (or the community `convex_flutter` client) before building on it.
- **R2 — cross-platform subscription reconciliation:** store IAP vs web Stripe. Mitigation: RevenueCat as the single source of entitlement truth; Convex mirrors it.
- **R3 — cost control on the subscription tier:** metered limits enforced server-side in Convex; hard caps per plan.
- **R4 — web ≠ on-device:** web is online-only (no browser ML). Set expectations in UX; the "same app" promise is account/experience parity, not offline-in-browser.

## 8. First step

**O0 — Flutter ↔ Convex spike:** a throwaway proof that the Flutter app can authenticate to Convex and call a server function (e.g., an `echo`/`whoami` httpAction) with the session token. Go/no-go on the mobile↔Convex integration before O1.
