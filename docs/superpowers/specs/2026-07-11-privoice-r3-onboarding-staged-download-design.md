# R3 — Onboarding + staged/background download

**Date:** 2026-07-11
**Status:** Approved design
**Workstream:** Redesign R3 (see STATUS.md)

## Problem

First launch currently shows a **hard gate** (`ModelGate` → `ModelDownloadScreen`)
that blocks the entire app behind a ~1.5 GB foreground download (STT Parakeet
~680 MB + Llama 3.2 1B ~808 MB) with the screen pinned on via wakelock. The user
sees nothing of the app until the whole download finishes, and leaving the screen
risks interrupting it.

## Goal

Let the user into the app immediately after a short onboarding, and download the
default model set **in the background** while they explore. Features unlock as
their model lands: **Record** when STT is ready, **AI actions** when the LLM is
ready ("staged").

Non-goals: OS foreground-service downloading (possible later follow-up), changing
the Settings opt-in 3B download, requesting mic permission during onboarding
(stays lazy, at first record).

## Decisions (from brainstorming)

- **UX model:** explore-while-downloading. App is usable right after onboarding;
  models stream in behind it, features unlock per-model.
- **Onboarding:** short 3-screen intro, then the app opens.
- **Background depth:** in-process resilient. Reuse the existing `ModelDownloader`
  (HTTP Range resume already built in). Continues while navigating the app; if the
  OS suspends/kills the process, the next launch auto-resumes from bytes on disk.
  No new native dependency, no notification, no wakelock.

## Architecture

### Entry point / bootstrap (`main.dart`)
Replace `ModelGate` in `MaterialApp.home` with a small bootstrap widget:

- **First launch** (`SettingsService.onboardingComplete == false`):
  show `OnboardingFlow`. On finish → set the flag, call
  `ModelManager.instance.ensureDefaultSet()`, navigate to `HomeScreen`.
- **Later launches** (flag `true`): go straight to `HomeScreen`; bootstrap also
  calls `ensureDefaultSet()`, which auto-resumes any not-fully-installed model and
  no-ops when everything is present.

### `ModelManager` (new — `apps/mobile/lib/model_manager.dart`)
A singleton `ChangeNotifier` wrapping `ModelDownloader` (reused unchanged).

- **Per-model state:** `notInstalled → downloading(fraction, phase) → extracting →
  ready → error(message)`.
- **Derived getters:** `sttReady`, `llmReady`, `overallFraction`, `hasError`.
- **`ensureDefaultSet()`:** iterates `ModelCatalog.defaultSet` **sequentially, STT
  first** (so recording unlocks soonest), then Llama 1B. Drives
  `ModelDownloader.install(spec, onProgress)` and republishes progress via
  `notifyListeners()`. Skips models already installed. Safe to call repeatedly
  (idempotent; a call while a download is in flight is a no-op).
- **No wakelock.** In-process; suspension is recovered by resume-on-next-launch.
- **Testability:** never self-starts. The download only begins when
  `ensureDefaultSet()` is explicitly called, and the manager accepts an injected
  downloader, so widget tests and the zero-network privacy gate stay green.

### Onboarding (`apps/mobile/lib/screens/onboarding_flow.dart`)
Three swipeable screens using the existing R1 calm-teal tokens:

1. **Welcome** — what Privoice does (record → transcribe → summarize).
2. **Private by design** — everything runs on-device; "On-device" lock motif;
   nothing uploaded.
3. **Getting you set up** — "We're downloading your on-device models (~1.5 GB).
   You can start exploring now — best on Wi-Fi." Primary button **Start** →
   commits (sets flag, starts download, enters app).

Page dots + Skip/Next; the final screen's **Start** button is the commit point.

### Per-feature "getting ready" states
- **Home:** slim progress banner above the meeting list while any default model is
  downloading — "Setting up Privoice · 62%" — with a **Retry** affordance when in
  `error`. Hidden once both models are `ready`. Home listens to `ModelManager`.
- **Record FAB:** until `sttReady`, rendered in a "Preparing…" style; tapping shows
  a snackbar ("Speech-to-text is still downloading (45%)") instead of opening
  `RecordScreen`. Normal Record once `sttReady`.
- **AI smart actions** (transcript screen): Summarize / Minutes / Ask disabled with
  a "Preparing AI…" hint until `llmReady`; enabled after.

### Settings persistence (`settings.dart`)
Add `onboardingComplete` (bool, SharedPreferences), mirroring the existing
`useLargeModel` / `themeMode` pattern.

## Error handling

Per-model `error` state surfaces in the Home banner with **Retry**, which
re-invokes `ensureDefaultSet()` and resumes from bytes already on disk. Features
stay locked until their model reaches `ready`. Onboarding never blocks on the
download — a failed download is recoverable from inside the app.

## Testing

- **Onboarding widget test:** advances through the 3 screens; **Start** sets
  `onboardingComplete` and triggers the (fake) manager.
- **`ModelManager` state-machine test** with a fake downloader:
  `notInstalled → downloading → extracting → ready`, and `error → Retry → ready`;
  `ensureDefaultSet()` is idempotent and STT-before-LLM ordered.
- **Home gating test:** Record shows "Preparing…" when `!sttReady`, enabled when
  `sttReady`; banner visible while downloading, hidden when ready.
- **Regression:** existing suite + zero-network privacy gate stay green (manager
  does not self-start; no HTTP client created in the offline transcription flow).

## Affected files

- New: `apps/mobile/lib/model_manager.dart`,
  `apps/mobile/lib/screens/onboarding_flow.dart`.
- Edit: `apps/mobile/lib/main.dart` (bootstrap replaces `ModelGate`),
  `apps/mobile/lib/settings.dart` (+`onboardingComplete`),
  `apps/mobile/lib/screens/home_screen.dart` (banner + FAB gating),
  `apps/mobile/lib/screens/transcript_screen.dart` (AI action gating).
- Removed/retired: `apps/mobile/lib/screens/model_gate.dart` (superseded).
  `model_download_screen.dart` stays — still used by the Settings 3B flow.
