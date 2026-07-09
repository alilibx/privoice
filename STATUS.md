# Privoice — Project Status

**Last updated:** 2026-07-10
**Now:** On-device record → transcribe → save works end-to-end on a real Android phone. STT is proven (Parakeet-TDT v3 INT8, RTF 0.44 on a low-end device). Next: on-device summary/minutes + chat.

> ⚠️ **This file is the single source of truth for progress.** Read it at the start of every work session and update it whenever a task/feature changes status. See CLAUDE.md.

**Legend:** ✅ done · 🔨 in progress · ⬜ todo · 🧪 validated by spike

---

## Build slices

| ID | Slice | Status | Notes |
|----|-------|--------|-------|
| S0 | Toolchain bootstrap + melos monorepo | ✅ | Flutter 3.44.5, JDK17, Android SDK 36 |
| S1 | On-device STT spike | ✅ 🧪 | **GO** — real device (Redmi 15C), RTF 0.44, perfect on clean sample |
| S2 | Record → Transcribe UI + persistence | ✅ | Off-thread STT, SQLite, calm/trustworthy theme. Merged to main |
| S3 | On-device LLM: summary / minutes (map-reduce) | ⬜ | Next. fllama + Llama 3.2 3B / Gemma 2 2B. Also unblocks chat |
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
- SQLite persistence · Home / Record / Transcript screens · Copy transcript
- Calm & trustworthy Material 3 theme · "On-device" privacy badge

**Todo ⬜**
- Summary / minutes (LLM) · Map-reduce for long meetings · Custom minutes templates
- Export PDF · Export Word (.docx)
- In-app model download · Device tiering (auto model select) · "Go higher" toggle + warning
- Speaker diarization
- General-assistant chat panel · Chat grounded in meeting + documents
- Document parse: PDF · DOCX · MD/TXT
- Tier-selectable AI engine (on-device default + online BYO) · Online STT provider
- Settings screen · Audio playback · Rename meeting · Delete-from-UI (repo delete exists, no button yet)
- Recording pause/resume · live audio level meter

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
