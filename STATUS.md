# Privoice — Project Status

**Last updated:** 2026-07-11
**Now:** Full on-device flow (onboarding → record → transcribe → summarize) **working on the Redmi**. Redesign R1–R6 done + **on-device verified**; **reliable model download shipped + verified**. **R1** calm-teal tokens + light/dark/system theme ✅ · **R2** perceived-perf (LLM streaming, reuse, warm-up) ✅ · **R3** onboarding + background download ✅ · **R4** library-first Home ✅ · **R5** Record screen + live scrolling waveform ✅ · **R6** Overview/Transcript meeting screen (auto-generate, checkable action items, AI title, rename, share) ✅ *(verified, Redmi)*. **Testing:** T0 ✅ · T1 🔨 (privacy ✅) · T2 ✅ (CI) · T3 ✅ (Test Lab). **Next major workstream: Web version (Privoice Cloud — Next.js + Convex), then online tier → iOS → desktop.** (R7 polish + S4 export remain Android-app backlog.)

**Redesign (R1–R7):** R1 tokens+theme ✅ *(verified)* · R2 perceived-perf ✅ *(verified)* · R3 onboarding + background download ✅ *(verified, Redmi)* · R4 library-first Home ✅ *(verified — grouped list Today/This week/Earlier + status dots + persistent bottom record dock; FAB/toggle-search retired)* · R5 Record + live waveform ✅ *(verified — mic-amplitude scrolling waveform, `AudioRecorderHandle.levels()`)* · **R6 minutes/transcript ✅ *(verified, Redmi)*** — Overview-first (default) + Transcript tabs; auto-generates minutes → checkable action items → AI title on first open (guarded, streamed, preparing/retry states); persisted done-state (schema v3 migration); inline rename (auto-title only overwrites the `Meeting D/M HH:MM` placeholder); per-section share + copy-all; disabled Export stub; persistent Ask entry. · **R7 empty/error states + delight ⬜ (next)**.

## ▶ What's next (priority order)

1. **Web version — Privoice Cloud (Next.js + Convex)** *(next major workstream)* — start the web app + cloud backend. Begin with **O0** (Flutter↔Convex spike) → **O1** (Convex backend + shared auth + Next.js scaffold w/ login). New sub-project: brainstorm → spec → plan → build. See the cloud + multi-platform spec. Then **2. Online tier** (O2/O3/O5), **3. iOS**, **4. Desktop** — see the Platform build order below.
2. **R7 — empty/error states + delight** *(Android backlog)* — final redesign polish pass across screens; can slot around the web work.
3. **S4 — Export (PDF + Word .docx)** *(Android backlog)* — real functional gap; the R6 Export stub is wired and waiting.
4. **On-device quality harnesses** — **T4** STT WER (accents/crosstalk/far-mic/**Arabic** — evaluate Cohere Transcribe here) + **T6** perf/thermal → device-tier→model table. Both need on-device runs.
5. **Deferred / opt-in follow-ups** — **S9** global assistant chat (all meetings + external docs); resume-hardening on-device pass; own-bucket mirror for the 4 STT files (drops HF reliance); golden tests + nightly Test Lab; S7 document parsing.

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
| S5 | In-app model download | ✅ *(reworked, verified)* | Foreground-service download (`background_downloader`) — resumes across backgrounding/screen-off/swipe-away. **STT now downloads as 4 pre-extracted files from HF** (no in-app tar.bz2 extraction — removed the ~6-min/48% on-device stall). Default 1B; 3B opt-in in Settings. App reads from app-owned dir. *Device auto-tiering* still ⬜ (manual toggle for now). Own-bucket mirror for the STT files = optional follow-up (drops HF reliance) |
| S6 | AiEngine + on-device chat panel | ⬜ | General-assistant chat, grounded in meeting/docs → folded into **S9** (global assistant across all meetings + external docs) |
| S7 | Document parsing (PDF / .docx / .md·txt) | ⬜ | Feeds summary + chat context |
| S8 | Online tier (OpenRouter BYO key + curated list) | ⬜ | Off by default; privacy-gated |
| S9 | **Global assistant chat (all meetings + external docs)** | ⬜ | ChatGPT-like standalone chat, same feel as the per-meeting **Ask** sheet but scoped across **all** meetings, and able to ingest **external documents** as knowledge (not tied to any meeting). RAG over meetings + docs; on-device default, online tier optional. Superset of S6 (per-meeting Ask) + S7 (doc parse) |
| — | **STT model eval: Cohere Transcribe (Arabic)** | ⬜ | Evaluate [`CohereLabs/cohere-transcribe-03-2026`](https://huggingface.co/CohereLabs/cohere-transcribe-03-2026) as an **Arabic-capable** STT alternative/complement to Parakeet (GCC market). Check licence, size, on-device feasibility (vs server-side), latency/RTF; swappable behind `SttEngine`. Feeds **T4** Arabic WER |
| — | Speaker diarization (sherpa-onnx) | ⬜ | Speaker labels in transcript |
| P4 | Private GPU infra (self-hosted, zero-retention, GCC) | ⬜ | Future sub-project — own spec |
| P5 | Proprietary meeting-STT model | ⬜ | Future sub-project — own spec |

---

## Platforms & new programs (planned)

Privoice is now a **multi-platform suite** from one Flutter codebase + a web/cloud layer.

**▶ Platform build order (current priority, per product direction 2026-07-11):**
**1. Web** (Next.js + Convex) → **2. Online tier** (mobile routes AI online; billing/BYOK) → **3. iOS** (Flutter) → **4. Desktop** (Flutter, macOS first). Web is the **next major workstream**; the redesign-track polish (R7) and Export (S4) stay as near-term Android-app backlog and can slot around it.

**Target platforms**
| Platform | Tech | Capability | Priority | Status |
|---|---|---|---|---|
| Android | Flutter | on-device | shipped | ✅ working |
| Web | Next.js + React | online tier only | **1 (next)** | ⬜ new |
| Online tier (mobile) | Convex + OpenRouter | opt-in online | **2** | ⬜ new |
| iOS | Flutter | on-device | **3** | ⬜ |
| macOS / Windows / Linux | Flutter (same codebase) | on-device | **4** (macOS first) | ⬜ new |

### Desktop (Flutter, offline) — reuses audio/stt/ai packages
| ID | Item | Status | Notes |
|----|------|--------|-------|
| D0 | Enable desktop platforms + verify sherpa/fllama/record build on macOS | ⬜ | macOS first (buildable here) |
| D1 | Platform adaptation: `sqflite_common_ffi` on desktop + `PlatformPaths` (model/storage per OS) | ⬜ | Path logic shared with S5 |
| D2 | Desktop UX pass (window sizing, menus) + Windows/Linux | ⬜ | |

### Online Platform — "Privoice Cloud" (Convex backend + Next.js web + online tier)
Opt-in, off by default. Stack: **Convex** (auth, DB, functions, file storage) · **Next.js/React** web · **RevenueCat** billing · **OpenRouter** models. Own spec.
**Decision (2026-07-11):** the **web app is online-tier only — transcription runs server-side** (no in-browser/WASM STT); on-device STT stays the mobile/desktop story. Server STT provider TBD (OpenRouter/Cohere Transcribe — the Arabic eval feeds this).
| ID | Item | Status | Notes |
|----|------|--------|-------|
| O0 | **Flutter ↔ Convex spike** | ✅ 🧪 *(GO, 2026-07-12)* | De-risked (`spikes/o0-convex/`). **HTTP-action transport from Dart proven headlessly** (smoke: GET /ping + POST /echo 200 against `colorless-mammoth-659`). **`convex_flutter` v3.0.1** confirmed viable (Android/iOS/web/desktop; Rust FFI; subscribe/mutation/setAuth) — community pkg, pin it. **Key reframing:** web app uses Convex's **official `convex/react`** client (near-zero risk); `convex_flutter` only matters for mobile online tier. **Deferred → O5:** on-device convex_flutter run (native load + WS + auth + file upload). Not blocking web |
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
- **Live recording waveform** (mic-amplitude level meter, scrolling)
- SQLite persistence · Home / Record / Transcript screens
- **Summarize → minutes (LLM) · Map-reduce · Action items · Ask (chat grounded in meeting)**
- **R6 meeting screen:** Overview (default) + Transcript tabs · auto-generate minutes+items+title on open · **checkable, persisted action items** (schema v3) · **AI-generated meeting title** · **inline rename** · per-section share + copy-all · disabled Export stub · persistent Ask entry
- **Animations:** record pulse rings · staggered list entrance · minutes reveal · action-chip stagger · typing indicator
- Search meetings · Swipe-to-delete + undo · Share (minutes/transcript) · Copy
- Elevated calm-teal Material 3 theme (light/dark/system) · "On-device" privacy badge
- **In-app model download** (foreground service, resumable, no extraction) · first-launch onboarding · Settings (1B/3B toggle) · library-first Home · Record screen w/ live waveform

**Todo ⬜**
- Custom minutes templates · Export PDF · Export Word (.docx)
- Device tiering (auto model select) · "Go higher" toggle + warning
- Speaker diarization
- Standalone chat panel (beyond per-meeting Ask) · Chat over documents
- Document parse: PDF · DOCX · MD/TXT
- Tier-selectable AI engine (on-device default + online BYO) · Online STT provider
- Settings screen · Audio playback
- Recording pause/resume

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

- **R6 schema v3 (action items):** `Meeting.actionItems` is now `List<ActionItem>` (`text` + persisted `done`), serialized as JSON in the `action_items` column; `onUpgrade` v2→v3 converts legacy newline rows in place, and `fromRow` also reads the legacy form as a fallback. **On-device (Redmi) verification of the v3 migration on a real pre-R6 DB is outstanding.** Deferred non-blocking minors (from final review): `Meeting._decodeActionItems` catches `FormatException` but a `e as Map` cast could `TypeError` on *externally*-corrupted JSON (our writer never emits that); the migration loop isn't in an explicit transaction (sqflite bumps `user_version` only after `onUpgrade` returns and the loop is idempotent, so a killed migration re-runs cleanly).
- **R6 auto-generate is on-device-only to fully exercise:** widget tests use a synchronous fake AI; the streamed generation, the "Preparing on-device AI" hold (LLM still downloading), and the first-run Retry path need a real device run to confirm feel/timing.

- **Model delivery:** S5 in-app download + R3 first-launch staged/background download now cover model delivery for a real install (onboarding → background download → per-model unlock, resumes on relaunch). **On-device (Redmi) confirmed the deferred risk:** the in-process download stalls when the screen auto-locks (OS suspends the process, drops the socket). **Mitigated (R3):** a screen wakelock while downloading (now redundant, retained). **Reliable download done (code-complete; on-device pending):** downloads run via `background_downloader` 9.5.5 with `Config.runInForeground` + a progress notification (backgrounded/screen-off safe). **STT no longer ships as a tar.bz2** — it downloads as the **4 pre-extracted files** direct from HF (`csukuangfj/...parakeet-tdt-0.6b-v3-int8`), so there is **no in-app decompression** (kills the on-device ~6-min 100%-CPU / stuck-at-48% extraction). Transport uses **`enqueue` + `start(doRescheduleKilledTasks)` + stable task ids** so an interrupted download **resumes across process-death/swipe-away** (already-downloaded files skipped on relaunch). `updates` wrapped as a broadcast stream (multi-file/concurrent safe). Notification no longer falsely says "ready" (in-app banner is the source of truth). `ModelDownloader`/`ModelManager` interfaces unchanged; `archive` dep removed. Onboarding gained a 4th page priming `POST_NOTIFICATIONS`. Files land in `applicationSupport/models/<subdir>` (matches `PlatformPaths`). Build-verified (native plugin compiles); **on-device Redmi verification outstanding** (fresh install = smooth, no extraction stall; lock/background/swipe-away mid-download → resumes). Manual `adb push` (flat `files/` root) remains only a dev/test convenience.
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
*(Android on-device MVP is complete + verified through R6. Direction as of 2026-07-11 pivots to multi-platform.)*
1. **Web version — Privoice Cloud** (Next.js + Convex): **O0** spike → **O1** backend + auth + web scaffold → web UI + **O4** chat-with-docs
2. **Online tier** for mobile: **O2** billing/BYOK → **O3** AI proxy → **O5** mobile online client
3. **iOS** (Flutter) enablement
4. **Desktop** (Flutter, macOS first): **D0–D2**
5. *Android backlog, slot around the above:* **R7** delight polish · **S4** export · **S9** global assistant chat (all meetings + external docs) · **T4** Arabic WER (eval Cohere Transcribe) · diarization
