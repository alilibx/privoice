# S1 STT Spike — Benchmark Results

**Date:** 2026-07-09
**Verdict:** ✅ **GO** — on-device Parakeet-TDT v3 INT8 via sherpa-onnx is fast and accurate, even on a low-end device.

## Setup

| | |
|---|---|
| Device | **Redmi 15C** (physical) |
| SoC | **MediaTek Helio G (MT6769)** — budget/entry-class CPU |
| RAM | 8 GB (7.85 GB total) |
| OS | Android 15 (SDK 35), arm64-v8a |
| Framework | Flutter 3.44.5 |
| STT | sherpa-onnx **1.13.4** (Dart binding) |
| Model | `sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8` (transducer, INT8) |
| Sample | model's bundled `test_wavs/en.wav` (JFK line, 3.85 s, clean) |

## Results

| Metric | Value | Notes |
|---|---|---|
| **Accuracy** | **Perfect** on the clean sample | Output: *"Ask not what your country can do for you, ask what you can do for your country."* |
| **RTF (inference)** | **0.44** | 3,845 ms audio → 1,690 ms transcribe = ~2.3× faster than real-time |
| **First-run model load** | ~8 s (one-time) | mmap of the 622 MB encoder; amortized over the meeting |
| **RAM (PSS)** | **~300 MB** | RSS ~430 MB. ONNX Runtime **mmaps** the model, so it is not fully resident |
| **Model size on disk** | **643 MB** | encoder 622 MB + decoder 11 MB + joiner 6 MB + tokens 0.09 MB |
| **Android build** | ✅ builds & bundles native libs | `libonnxruntime.so` + `libsherpa-onnx-c-api.so` for arm64/armv7/x86_64 |

## Interpretation

- **Viability confirmed on a worst-case CPU.** A budget Helio G runs inference at ~0.44 RTF with perfect accuracy on clean speech. Flagships (Snapdragon 8-class, Apple ANE) will be substantially faster. This validates the plan's offline-first premise.
- **RAM is a non-issue.** ~300 MB PSS (mmap) means even 3–4 GB phones can run the STT stage. The device-tier RAM ceiling is set by the LLM stage, not STT.
- **Sequential post-processing is comfortable.** At ~0.44 RTF a 60-min meeting transcribes in ~26 min of background work on this low-end device; much faster on better hardware.

## Caveats / still to validate

- **Clean sample only.** Real meeting audio (accents, crosstalk, poor mics, far-field) will raise WER. Needs a real-meeting WER benchmark (Section 8 of the project plan).
- **Short clip.** Sustained RTF over a full 1-hour recording (and any thermal throttling) not yet measured on real long audio.
- **Diarization** not tested here (deferred slice).
- Numbers are for **INT8 Parakeet**; a whisper.cpp base/small A/B on the same device would confirm the model choice, but Parakeet already clears the bar.

## How this was measured

Model + sample pushed **flat** into the app's external files dir; the app's sentinel-gated `SpikeScreen._maybeSelfTest` auto-transcribes on launch and logs `ITEST_STT`. See `tools/emulator-stt-test.sh` (works for physical devices too). Note: files must be pushed **flat** into the app-owned `files/` root — adb-created nested subdirs aren't readable by the app under scoped storage (a test-injection artifact only; the real download flow writes as the app and is unaffected).

Raw log:
```
ITEST_DIAG base=/storage/emulated/0/Android/data/com.privoice.mobile/files sentinel=true encoder=true wav=true
ITEST_STT rtf=0.44 audioMs=3845 transcribeMs=1690 text="Ask not what your country can do for you, ask what you can do for your country."
```
