# Privoice — Project Status

**Last updated:** 2026-07-10
**Now:** Record → transcribe → save works on a real phone (STT proven, RTF 0.44). On-device LLM proven (Llama 3.2 1B via fllama → clean minutes in 6.1s). Smart-actions UI (Summarize / Action items / Ask) + animations built. Testing strategy defined ([TESTING.md](TESTING.md)) — real-device matrix + ML-quality harness planned.

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
| S5 | In-app model download + device tiering | ⬜ | Makes app self-sufficient (no adb push) |
| S6 | AiEngine + on-device chat panel | ⬜ | General-assistant chat, grounded in meeting/docs |
| S7 | Document parsing (PDF / .docx / .md·txt) | ⬜ | Feeds summary + chat context |
| S8 | Online tier (OpenRouter BYO key + curated list) | ⬜ | Off by default; privacy-gated |
| — | Speaker diarization (sherpa-onnx) | ⬜ | Speaker labels in transcript |
| P4 | Private GPU infra (self-hosted, zero-retention, GCC) | ⬜ | Future sub-project — own spec |
| P5 | Proprietary meeting-STT model | ⬜ | Future sub-project — own spec |

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
| T0 | Test foundation: fakes (repo/STT/AI) + expand unit + widget tests (3 screens) | ⬜ | Have: map_reduce, recording_config, transcript, benchmark unit tests |
| T1 | Golden tests (light/dark) + summarize integration test + **airplane-mode privacy gate** | ⬜ | Zero-network assertion is a hard gate |
| T2 | CI pipeline (analyze + tests + debug build) on PRs; pick runner (GH Actions / Codemagic) | ⬜ | Debug build catches sherpa/fllama native breakage |
| T3 | Real-device matrix on a cloud farm (Firebase Test Lab primary) — nightly integration + perf | ⬜ | Android low/mid/high tiers; iOS later |
| T4 | STT WER harness + real-meeting corpus (accents, crosstalk, far mic, Arabic) | ⬜ | |
| T5 | LLM minutes quality eval (rubric + LLM-as-judge) per model tier | ⬜ | |
| T6 | Perf/thermal/battery harness → **device-tier→model table** (feeds S5) | ⬜ | |
| T7 | Accessibility + **Arabic / RTL** pass (GCC market) | ⬜ | |
| T8 | Automated release gates + quality dashboard | ⬜ | |

**Current automated coverage:** unit tests in all 4 packages + app (`melos run test`); one STT integration test; sentinel-gated on-device STT & LLM self-tests. **Gaps:** no widget/golden tests, no CI, no device matrix, no ML-quality/perf harness yet.

---

## Known gaps / tech debt

- **Model delivery:** model is only present via manual `adb push` (flat `files/` root). S5 in-app download is required for a real app.
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
- Design spec: `docs/superpowers/specs/2026-07-09-privoice-monorepo-phase1-mvp-design.md`
- S0–S1 plan: `docs/superpowers/plans/2026-07-09-privoice-s0-s1-bootstrap-and-stt-spike.md`
- STT benchmark: `docs/superpowers/benchmarks/2026-07-09-stt-spike-results.md`
- Toolchain bootstrap: `tools/bootstrap-macos.md`

---

## Recommended next order
1. **S3** on-device LLM spike → summary/minutes (de-risks LLM + unblocks chat)
2. **S5** in-app model download (self-sufficient app)
3. **S6** chat panel
4. **S4** export → then diarization, then S7 docs, then S8 online tier
