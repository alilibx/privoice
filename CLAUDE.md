# CLAUDE.md — Privoice

Privacy-first meeting transcription app (Flutter, Android-first). Record → transcribe → summarize → export, **fully on-device by default**. Later: online tiers + private GPU infra.

## ⚠️ Always use STATUS.md

**[STATUS.md](STATUS.md) is the single source of truth for progress.**

- **At the start of every session:** read `STATUS.md` to see what's done and what's next.
- **Whenever a task or feature changes status** (started, finished, blocked, descoped): update `STATUS.md` in the same change — flip the ✅/🔨/⬜ marker, update "Last updated", and adjust the gaps/next-order sections.
- Treat "update STATUS.md" as part of *done*, not an afterthought. A task isn't complete until STATUS.md reflects it.
- Keep it honest: mark things ✅ only when actually verified (tests pass / ran on device), not when code is merely written.

## Architecture

Melos monorepo. `apps/mobile` (Flutter app) depends on `packages/*`; packages never depend on the app.

- `packages/core` — Meeting model + `MeetingRepository` (sqflite)
- `packages/audio` — 16 kHz mono WAV recording (`record`)
- `packages/stt` — sherpa-onnx transcription behind `SttEngine`; `transcribeFileInBackground` (isolate)
- `packages/ai` *(planned)* — `AiEngine` (on-device fllama + online OpenRouter): summary/minutes + chat
- `packages/documents` *(planned)* — parse PDF/.docx/.md → context

All native-binding code stays inside its package, behind a clean Dart interface, so backends are swappable.

## Common commands

```bash
export PATH="/opt/homebrew/bin:$HOME/.pub-cache/bin:/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH"
export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"

melos run analyze          # analyze all packages (must be clean)
melos run test             # run all package tests
cd apps/mobile && flutter build apk --debug
```

## Device workflow (Redmi 15C test phone)

`adb install` is blocked on this Xiaomi (needs SIM). Sideload instead:
```bash
adb -s <serial> push apps/mobile/build/app/outputs/flutter-apk/app-debug.apk /sdcard/Download/privoice.apk
# then tap privoice.apk on the phone to install/update
```
STT model must be pushed **flat** into the app's `files/` root (see `tools/emulator-stt-test.sh`). Full device/env facts live in STATUS.md.

## Conventions

- Follow existing patterns; keep files focused (one clear purpose).
- Conventional commits; branch off `main` for each slice, merge `--no-ff` when verified.
- Privacy invariant: on-device by default; any online/cloud path is opt-in, clearly labelled, and off by default.
