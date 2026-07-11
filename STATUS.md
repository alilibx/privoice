# Privoice — Project Status

**Last updated:** 2026-07-11
**Now:** On-device record→transcribe→summarize works; **S5 model download done** (resumable, extraction verified). **Redesign underway** (mockups approved). **R1 done + on-device verified:** elevated calm-teal tokens + **light/dark/system theme setting** (live switch, persisted). **R2 perceived-perf landed:** LLM streaming, result reuse, no double-work, warm-up. **R3 onboarding + staged/background download landed (code-complete):** first-launch 3-screen intro, then the app opens while STT+LLM download in the background via `ModelManager`; Record unlocks on STT, AI actions on LLM; `ModelGate` retired. Automated-verified (26 tests + debug build); full on-device onboarding/download walkthrough still pending. **Testing:** T0 ✅ · T1 🔨 (privacy ✅) · T2 ✅ (CI) · T3 ✅ (Test Lab).

**Redesign (R1–R7):** R1 tokens+theme ✅ · R2 perceived-perf ✅ (streaming/reuse/warm-up) · R3 onboarding + staged/background download ✅ *(code-complete; on-device walkthrough pending)* — 3-screen intro + in-process resilient background download (`ModelManager`), per-model feature gating (Record↔STT, AI↔LLM), `ModelGate` retired · R4 home ⬜ · R5 record ⬜ · R6 minutes ⬜ · R7 empty/error states + delight ⬜. Next: verify R3 on device (Redmi), then R4 home; T4 STT WER harness / T6 perf-thermal (both need on-device runs), golden tests, nightly Test Lab.

> ⚠️ **This file is the single source of truth for progress.** Read it at the start of every work session and update it whenever a task/feature changes status. See CLAUDE.md.

**Legend:** ✅ done · 🔨 in progress · ⬜ todo · 🧪 validated by spike

---

## Build slices

| ID | Slice | Status | Notes |
|----|-------|--------|-------|
| S0 | Toolchain bootstrap + melos monorepo | ✅ | Flutter 3.44.5, JDK17, Android SDK 36 |
| S1 | On-device STT spike | ✅ 🧪 | **GO** — real device (Redmi 15C), RTF 0.44, perfect on clean sample |
| S2 | Record → Transcribe UI + persistence | ✅ | Off-thread STT, SQLite, calm/trustworthy theme. Merged to main |
| S3 | On-device LLM: summary / minutes (map-reduce) | ✅ 🧪 | Works on-device (Llama 3.2 1B via fllama). Smart-actions UI shipped. 3B quality tier + quality eval pending (T5) |
| S6 | AiEngine + chat | 🔨 | **Ask** sheet (chat grounded in a meeting) done; standalone chat panel + tier-selectable online engine later |
| S4 | Export (PDF + Word .docx) | ⬜ | |
| S5 | In-app model download | ✅ | Gate + streamed download + **resumable** (HTTP Range) + wakelock; **tar.bz2 extraction verified** on the real 487MB artifact (all 4 files). App reads from app-owned dir. Default 1B; 3B opt-in in Settings. FB Storage mirror **deferred** (org blocks public buckets) → returns as authenticated read in the cloud tier. *Device auto-tiering* still ⬜ (manual toggle for now) |
| S6 | AiEngine + on-device chat panel | ⬜ | General-assistant chat, grounded in meeting/docs |
| S7 | Document parsing (PDF / .docx / .md·txt) | ⬜ | Feeds summary + chat context |
| S8 | Online tier (OpenRouter BYO key + curated list) | ⬜ | Off by default; privacy-gated |
| — | Speaker diarization (sherpa-onnx) | ⬜ | Speaker labels in transcript |
| P4 | Private GPU infra (self-hosted, zero-retention, GCC) | ⬜ | Future sub-project — own spec |
| P5 | Proprietary meeting-STT model | ⬜ | Future sub-project — own spec |

---

## Platforms & new programs (planned)

Privoice is now a **multi-platform suite** from one Flutter codebase + a web/cloud layer.

**Target platforms**
| Platform | Tech | Capability | Status |
|---|---|---|---|
| Android | Flutter | on-device | ✅ working |
| iOS | Flutter | on-device | ⬜ later |
| macOS / Windows / Linux | Flutter (same codebase) | on-device | ⬜ new (macOS first) |
| Web | Next.js + React | online tier only | ⬜ new |

### Desktop (Flutter, offline) — reuses audio/stt/ai packages
| ID | Item | Status | Notes |
|----|------|--------|-------|
| D0 | Enable desktop platforms + verify sherpa/fllama/record build on macOS | ⬜ | macOS first (buildable here) |
| D1 | Platform adaptation: `sqflite_common_ffi` on desktop + `PlatformPaths` (model/storage per OS) | ⬜ | Path logic shared with S5 |
| D2 | Desktop UX pass (window sizing, menus) + Windows/Linux | ⬜ | |

### Online Platform — "Privoice Cloud" (Convex backend + Next.js web + online tier)
Opt-in, off by default. Stack: **Convex** (auth, DB, functions, file storage) · **Next.js/React** web · **RevenueCat** billing · **OpenRouter** models. Own spec.
| ID | Item | Status | Notes |
|----|------|--------|-------|
| O0 | **Flutter ↔ Convex spike** | ⬜ | De-risk mobile↔Convex (HTTP actions + auth token / `convex_flutter`) before committing |
| O1 | Convex backend + shared Auth + Next.js web scaffold w/ login | ⬜ | Accounts shared web + mobile |
| O2 | Subscription + BYOK: RevenueCat + web billing, entitlements in Convex | ⬜ | Sub = our OpenRouter key (metered); BYOK = user key |
| O3 | Online AI proxy (Convex action → OpenRouter) | ⬜ | Entitlement-gated |
| O4 | Web: AI chat with documents (upload → parse → RAG → chat) | ⬜ | Node parsing: pdf-parse/mammoth |
| O5 | Mobile online-tier client (settings toggle, route AI online) | ⬜ | |

**Monorepo goes polyglot:** add `apps/web` (Next.js) + `convex/` (backend) alongside the Flutter app; melos manages Dart, JS uses its own tooling.

---

## Feature checklist (fine-grained)

**Working ✅**
- Record 16 kHz mono WAV · On-device STT (Parakeet) · Background-isolate transcription
- SQLite persistence · Home / Record / Transcript screens
- **Summarize → minutes (LLM) · Map-reduce · Action items · Ask (chat grounded in meeting)**
- **Animations:** record pulse rings · staggered list entrance · minutes reveal · action-chip stagger · typing indicator
- Search meetings · Swipe-to-delete + undo · Share (minutes/transcript) · Copy
- Calm & trustworthy Material 3 theme · "On-device" privacy badge

**Todo ⬜**
- Custom minutes templates · Export PDF · Export Word (.docx)
- In-app model download · Device tiering (auto model select) · "Go higher" toggle + warning
- Speaker diarization
- Standalone chat panel (beyond per-meeting Ask) · Chat over documents
- Document parse: PDF · DOCX · MD/TXT
- Tier-selectable AI engine (on-device default + online BYO) · Online STT provider
- Settings screen · Audio playback · Rename meeting
- Recording pause/resume · live audio level meter

---

## Testing & Quality  → full strategy in [TESTING.md](TESTING.md)

World-class quality requires **real-device testing across a tier matrix** (emulators can't measure speed/RAM/thermal/battery for on-device ML). Workstream:

| ID | Item | Status | Notes |
|----|------|--------|-------|
| T0 | Test foundation: fakes (repo/AI) + unit + widget tests | ✅ | 28 tests: fakes, Meeting serialization, repository CRUD (ffi in-memory), prompts, map_reduce, Home + Transcript widget tests |
| T1 | Golden tests (light/dark) + **zero-network privacy gate** | 🔨 | **Privacy gate ✅** — `privacy_gate_test.dart` asserts the offline flow creates 0 HTTP clients (Dart layer); OS-level airplane check via device is the complement. Golden tests still ⬜ |
| T2 | CI pipeline (analyze + tests + debug build) on PRs | ✅ | **Green on GitHub Actions**: analyze + test (10m) and Android debug build incl. fllama/sherpa native (15m) both pass. Tests run sequentially to avoid the native-build race |
| T3 | Real-device matrix on Firebase Test Lab | ✅ | **Robo matrix green** on project `privoice-app`: virtual A11 + OnePlus Nord CE 3 Lite (A14) + Galaxy S22 (A16), no crashes/ANRs. `tools/run-test-lab.sh` (pick devices with capacity — oriole/redfin queue at 0). Follow-ups: nightly automation + instrumentation-on-FTL + perf capture |
| T4 | STT WER harness + real-meeting corpus (accents, crosstalk, far mic, Arabic) | ⬜ | |
| T5 | LLM minutes quality eval (rubric + LLM-as-judge) per model tier | ⬜ | |
| T6 | Perf/thermal/battery harness → **device-tier→model table** (feeds S5) | ⬜ | |
| T7 | Accessibility + **Arabic / RTL** pass (GCC market) | ⬜ | |
| T8 | Automated release gates + quality dashboard | ⬜ | |

**Current automated coverage:** **28 tests** (`melos run test`) — unit (serialization, repository CRUD via in-memory ffi, prompts, map-reduce, config, benchmark) + **widget tests** (Home: empty/list/search; Transcript: smart-action bar, summarize→minutes, action-item chips) with fakes for repo/AI. Plus one STT integration test + sentinel-gated on-device STT & LLM self-tests. CI workflow written. **Gaps:** golden tests, privacy zero-network gate, device matrix, ML-quality/perf harness, live CI run.

---

## Known gaps / tech debt

- **Model delivery:** S5 in-app download + R3 first-launch staged/background download now cover model delivery for a real install (onboarding → background download → per-model unlock, resumes on relaunch). **On-device (Redmi) confirmed the deferred risk:** the in-process download stalls when the screen auto-locks (OS suspends the process, drops the socket). **Mitigated:** `ModelManager` now holds a screen wakelock while downloading (best-effort; failures never abort the download), so a one-sitting setup completes — same approach S5 used. **Follow-up (still open): true OS foreground-service downloader** (`background_downloader` + progress notification + `POST_NOTIFICATIONS`) so downloads survive the app being backgrounded / swiped away and the screen turning off; the `ModelManager` interface stays the same. Manual `adb push` (flat `files/` root) remains only a dev/test convenience.
- **Cold-start cost:** first transcription per launch pays ~8 s model load (one-shot `compute` isolate). Optimize later with a warm long-lived isolate.
- **STT accuracy unvalidated on real meetings:** only clean sample tested. Need WER on accents/crosstalk/far-field + sustained RTF on 1-hour audio + thermal.
- **Spike harness retained:** `spike_screen.dart`, `benchmark.dart`, `integration_test/`, `tools/emulator-stt-test.sh` kept for re-benchmarking; not wired into the shipping app.
- **drift vs sqflite:** using sqflite for speed; spec mentioned drift. Swappable behind `MeetingRepository`.

---

## Environment facts (so nobody re-learns them)

- **Test device:** Redmi 15C — MediaTek Helio G (MT6769), 8 GB, Android 15, arm64-v8a. A good *low-end worst case*.
- **Xiaomi install quirk:** `adb install` fails `INSTALL_FAILED_USER_RESTRICTED` (Install-via-USB needs a SIM). Workaround: `adb push` APK to `/sdcard/Download` and tap-install on the phone.
- **Scoped-storage quirk:** the app reads adb-pushed files only from the **flat** app-owned `files/` root, not adb-created nested subdirs. Real download flow (S5) is unaffected.
- **Model:** `sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8` (643 MB), from k2-fsa releases tag `asr-models`.
- **Key versions:** sherpa_onnx 1.13.4, record 5.2.1 (+ override `record_platform_interface 1.5.0`, `record_linux 1.3.1`), sqflite 2.4.x.

---

## Reference docs
- **Testing & quality strategy: `TESTING.md`**
- Design spec (on-device MVP): `docs/superpowers/specs/2026-07-09-privoice-monorepo-phase1-mvp-design.md`
- **Cloud + multi-platform spec: `docs/superpowers/specs/2026-07-10-privoice-cloud-and-multiplatform-design.md`**
- S0–S1 plan: `docs/superpowers/plans/2026-07-09-privoice-s0-s1-bootstrap-and-stt-spike.md`
- STT benchmark: `docs/superpowers/benchmarks/2026-07-09-stt-spike-results.md`
- Toolchain bootstrap: `tools/bootstrap-macos.md`

---

## Recommended next order
1. **S3** on-device LLM spike → summary/minutes (de-risks LLM + unblocks chat)
2. **S5** in-app model download (self-sufficient app)
3. **S6** chat panel
4. **S4** export → then diarization, then S7 docs, then S8 online tier
