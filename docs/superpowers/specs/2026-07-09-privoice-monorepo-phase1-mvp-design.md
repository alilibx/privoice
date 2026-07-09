# Privoice — Monorepo + Phase-1 MVP Design

**Date:** 2026-07-09
**Status:** Approved (design), pending spec review
**Scope of this doc:** Sub-project 1 of the Privoice program — the monorepo scaffold and the Phase-1 lean offline MVP. Later sub-projects (online tiers, private GPU infra, proprietary STT) each get their own spec → plan → build cycle and are explicitly **out of scope** here.

---

## 1. Context & decisions

Privoice is a privacy-first meeting-transcription app: record → transcribe → summarize → export, fully **on-device by default**. The full program spans six phases; this sub-project builds the foundation and the beating heart (offline core).

Decisions made during brainstorming (with rationale):

| Decision | Choice | Why |
|---|---|---|
| Framework | **Flutter** (single Dart codebase) | The STT + diarization core is the product's value. `sherpa-onnx` (STT + diarization + VAD in one offline library) ships an **official first-party Dart binding**; React Native has only community wrappers. A shipped, fully-offline Flutter reference app ([`gabrimatic/local-whisper`](https://github.com/gabrimatic/local-whisper)) already wires this stack. |
| First platform | **Android** | The `sherpa-onnx` Dart path runs directly with the simplest toolchain and no Apple signing — fastest path to a running spike. Same Dart code later runs on iOS. |
| Monorepo tooling | **melos** (Dart workspace) | Standard Dart monorepo manager; clean package boundaries; polyglot-ready for future backend. |
| Build strategy | **Spike-first, then vertical slices** | The riskiest unknown (on-device STT perf/RAM/thermal on a real phone) is unverified. Prove and measure it before building UI around it. |
| MVP scope | **Lean core** | Record → Transcribe → Summarize (map-reduce) → Export, ONE fixed model per stage (fetched on first launch, not tier-selected), **no device tiering, no diarization** in v1. Each trimmed item returns as a fast-follow slice. |

**"Native" clarification:** we write **no** hand-authored native app code. Inference engines (ONNX Runtime, llama.cpp) are reached via Dart bindings (`sherpa_onnx`, `fllama`). The only place native code could appear is an *optional later* iOS WhisperKit/Core ML bridge — deferred, not required.

---

## 2. Recommended on-device stack (Phase 1)

- **Audio capture:** `record` (or `flutter_sound`) → 16 kHz mono WAV/PCM.
- **STT:** `sherpa-onnx` Dart binding, **NVIDIA Parakeet-TDT v3 INT8** ONNX model on Android. (Spike will A/B against a whisper.cpp small/base baseline to validate the plan's assumption.)
- **LLM (summary/minutes):** `fllama` (Dart FFI → llama.cpp), small Q4 model — **Llama 3.2 3B** or **Gemma 2 2B** as candidates; final pick driven by spike RAM/speed numbers.
- **Storage:** SQLite via `drift` for metadata/transcripts/minutes; audio + model files on the filesystem.
- **Export:** `pdf` package for PDF; a docx generator (HTML→docx or a Dart docx lib) for Word.

**Deferred to fast-follow / later phases:** device tiering + model-download manager, on-device diarization (sherpa-onnx supports it), iOS WhisperKit optimization, custom templates, online tiers.

### Open technical questions the spike must answer
The research confirmed the *path* but could not verify hard numbers (verifier infra errors). The spike resolves these on real hardware:
1. Real-time factor (RTF) of Parakeet-TDT v3 INT8 vs whisper.cpp base/small on a modern Android phone.
2. Peak RAM for STT alone, and for STT + a 1–3B Q4 LLM (sequential, since our pipeline is sequential).
3. Thermal/battery feel transcribing ~10 min of audio, extrapolated to 1 hour.
4. On-disk model size(s) → informs the eventual tiering table.
5. Which LLM (3B vs 2B) fits comfortably and produces coherent minutes via map-reduce.

---

## 3. Monorepo structure

```
privoice/
├── apps/
│   └── mobile/            # Flutter app: UI, navigation, wiring only
├── packages/
│   ├── core/              # shared types, drift (SQLite) storage, result/error types, utils
│   ├── audio/             # recording → 16kHz mono WAV; file management
│   ├── stt/               # sherpa-onnx wrapper: transcribe(file) -> Transcript (+ diarization later)
│   ├── llm/               # fllama wrapper: summarize/minutes, incl. map-reduce chunker
│   ├── models/            # model registry + (later) device tiering + download manager
│   └── export/            # Transcript/Minutes -> PDF and .docx
├── docs/
│   └── superpowers/specs/ # design docs (this file)
├── tools/                 # model-prep, benchmark, and dev scripts
├── melos.yaml
└── pubspec.yaml           # workspace root
```

**Principles:**
- Each package has one purpose, a small public interface, and is unit-testable without a device (using fixture audio/transcripts).
- `apps/mobile` depends on packages; packages do not depend on the app.
- We scaffold the skeleton up front (cheap) but only **implement what a slice needs**. The spike touches `audio` + `stt` only.
- Package interfaces are defined as abstract Dart classes so alternate implementations (e.g., an online STT backend in Phase 3) can slot in without touching the UI.

---

## 4. Data flow (Phase-1 pipeline — sequential, post-processing)

```
[Record screen] --stop--> WAV file (16kHz mono) on disk
      |
      v
[stt.transcribe(wavPath)] --(progress %)--> Transcript { segments[], fullText }
      |
      v
[llm.generateMinutes(transcript, template, userInstructions?)]
      |   map-reduce: chunk transcript -> per-chunk summaries -> reduce -> Minutes
      v
   Minutes { title, sections[], actionItems[] }
      |
      v
[export.toPdf(minutes) | export.toDocx(minutes)] --> file -> share sheet
```

All persisted in SQLite: a `Meeting` row (id, title, createdAt, audioPath, durationMs) with related `Transcript` and `Minutes`. The app is a list of past meetings + a record button.

**Error handling:** each stage returns a typed result (success / recoverable failure / fatal). Transcription and LLM stages are cancellable and report progress. A failed stage leaves the meeting in a resumable state (e.g., audio recorded but not yet transcribed) rather than losing data.

---

## 5. Build sequence (vertical slices)

Each slice ends in something runnable/demoable on the Android device.

- **S0 — Toolchain bootstrap** *(prerequisite)*: install Flutter, Android SDK, JDK; `flutter doctor` green for Android; init git; scaffold melos workspace + empty package skeleton.
- **S1 — STT spike:** minimal app: record a WAV → `sherpa-onnx` transcribe → show text + log RTF/RAM/model-size. Answers §2 open questions. **This is the go/no-go gate for the whole approach.**
- **S2 — Record→Transcribe UI:** real record screen, progress indicator, meeting list, transcript view, SQLite persistence.
- **S3 — Summarize:** `llm` package with `fllama` + map-reduce; generate minutes from transcript with the single default template.
- **S4 — Export:** minutes → PDF and .docx → system share sheet.
- **S5+ — Fast-follows:** device tiering + model download · diarization · manual "go higher" toggle · custom templates. (Each may warrant its own mini-spec.)

**Definition of done for the MVP:** on a real Android phone, record a meeting, get a transcript, get coherent minutes for a 30–60 min meeting, export a readable PDF and .docx — entirely offline (airplane mode).

---

## 6. Testing strategy

- **Package unit tests:** `llm` map-reduce chunking, `export` document generation, `core` storage — all testable on the host with fixtures, no device needed.
- **STT integration:** a checked-in short fixture WAV + expected-ish transcript; tolerance-based assertion (WER threshold), runnable on device/emulator.
- **Spike measurements** recorded in `tools/` as a reproducible benchmark script and a results doc, so the tiering table (later) is data-driven.
- Manual end-to-end offline test (airplane mode) is the MVP acceptance gate.

---

## 7. Explicitly out of scope (future sub-projects)

Online/BYO tier (OpenRouter + online STT), private GPU infra (self-hosted Whisper/pyannote/vLLM, zero-retention, GCC residency, SOC2/GDPR), enterprise billing, and the proprietary meeting-STT model. These are separate specs later. Package interfaces here are designed so the online STT/LLM backends can be added as alternate implementations without rework.

---

## 8. Risks & mitigations (this sub-project)

| Risk | Mitigation |
|---|---|
| On-device STT too slow / hot / RAM-heavy on real phones | S1 spike measures it first; go/no-go before further build. Fallback: smaller model / whisper.cpp base. |
| Small on-device LLM produces vague minutes on long meetings | Map-reduce built into `llm` from S3; spike validates 2B vs 3B output quality. |
| `sherpa-onnx` / `fllama` Dart binding rough edges on Android | Lean on the `local-whisper` reference app's wiring; isolate all binding code in `stt`/`llm` packages behind clean interfaces. |
| Toolchain not installed (confirmed) | S0 bootstrap is an explicit first step, not an assumption. |
| Model files bloat app binary | Models are downloaded/placed on first launch, not bundled in the APK. |
