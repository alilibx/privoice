# R5 — Record screen redesign + live waveform

**Date:** 2026-07-11
**Status:** Approved design
**Workstream:** Redesign R5 (see STATUS.md)

## Problem

The current Record screen (`apps/mobile/lib/screens/record_screen.dart`) is a
generic Material screen: a 56px timer, a 200px record button with red pulse
rings, and phase text (idle / recording / transcribing / error). It predates the
R1 calm-teal language and gives no live feedback that audio is being captured.

## Direction (from brainstorming + mockups)

Redesign to the calm-teal language and add a **live scrolling waveform** driven
by the microphone amplitude:

- **Idle** — muted `00:00`, a flat teal baseline waveform, a teal mic button,
  "Tap to start recording".
- **Recording** — a large tabular timer, a small red **● REC** indicator, and a
  **scrolling waveform**: each new bar is the latest mic level; the buffer scrolls
  right-to-left with older bars fading toward a light teal. A teal stop button
  ("Tap to stop & transcribe").
- **Transcribing** — calm teal sparkle + determinate progress + on-device line.
- **Error** — icon + message + Back, restyled to match.

Scope: redesign + live waveform. **No pause/resume** (deferred). No change to the
record→transcribe→persist pipeline.

## Amplitude in the audio package

`record` (wrapped by `AppAudioRecorder`) exposes `onAmplitudeChanged(interval)`
→ `Stream<Amplitude>` (dBFS). We surface a normalized level stream and keep the
dBFS→0..1 mapping in the package (pure + testable).

- **Interface (new):** `abstract class AudioRecorderHandle` with
  `Future<bool> hasPermission()`, `Future<void> start(String dirPath)`,
  `Future<String> stop()`, `Future<void> dispose()`, and
  `Stream<double> levels({Duration interval})` (normalized 0..1). This is the
  clean Dart seam the architecture calls for — the screen depends on it, tests
  fake it, `AppAudioRecorder` implements it.
- **`AppAudioRecorder implements AudioRecorderHandle`:** adds
  `levels({interval = 150ms})` mapping `AudioRecorder.onAmplitudeChanged(interval)`
  via a pure top-level `double normalizeAmplitude(double dbfs)`:
  `((dbfs - _floorDb) / -_floorDb).clamp(0, 1)` with `_floorDb = -50.0`
  (dBFS is ≤ 0; −50 or quieter → 0, 0 → 1).
- Both `AudioRecorderHandle` and `normalizeAmplitude` are exported from
  `privoice_audio.dart`.

## Waveform buffer (pure, in the app)

A small pure helper drives the scroll without any animation controller (so
`pumpAndSettle()` stays safe):

- `class RollingLevels { RollingLevels(this.capacity); void push(double level); List<double> get samples; }`
  — a fixed-capacity FIFO of the most recent normalized levels (oldest first),
  `capacity` ≈ 48 bars. Pushing past capacity drops the oldest. Unit-tested.
- The screen holds a `RollingLevels`, subscribes to `recorder.levels()`, and on
  each event `push`es and `setState`s. The waveform widget renders
  `samples` as bars (height ∝ level), newest at the right; bars fade with age
  (opacity/tint by index). No `AnimationController` — the stream cadence is the
  animation.

## Record screen changes

`record_screen.dart` rewritten:
- **Injectable recorder:** `RecordScreen({super.key, required MeetingRepository
  repository, AudioRecorderHandle? recorder})`; `_recorder = recorder ??
  AppAudioRecorder()`. All existing callers (`HomeScreen`) pass only
  `repository`, unchanged.
- **Phases** unchanged (`idle`, `recording`, `transcribing`, `error`); the
  record→`ModelLocator.parakeet()`→`transcribeFileInBackground`→persist→`pop(true)`
  pipeline is preserved verbatim, including the "model not found" and failure
  error messages.
- **Idle/recording UI** rebuilt per the mockup (timer, scrolling `_Waveform`,
  teal record/stop button, REC indicator, captions) using theme tokens.
- **Level subscription** starts on `_start`, is cancelled on stop and in
  `dispose` (alongside the existing ticker/recorder disposal).
- Transcribing + error states restyled to calm-teal (sparkle, determinate bar).

## Testing

- **Unit (audio):** `normalizeAmplitude` — `0.0 → 1.0`, `-50 → 0.0`,
  `-25 → 0.5`, `-160 → 0.0` (clamped), `10 → 1.0` (clamped).
- **Unit (app):** `RollingLevels` — respects capacity (drops oldest), preserves
  order (oldest→newest), handles empty/partial fill.
- **Widget (app):** with a `FakeAudioRecorderHandle` (permission granted, `start`
  no-ops, `levels` emits a controlled sequence, `stop` returns a dummy path):
  - idle shows the mic button + "Tap to start recording";
  - tapping start → recording state shows the timer, the stop control, and the
    waveform renders bars for the emitted levels;
  - the permission-denied path (fake returns `hasPermission()==false`) shows the
    error message.
  The stop→transcribe path (needs the real STT model) is left to the existing STT
  integration test / on-device; the widget test does not tap stop.
- **Regression:** full suite + zero-network privacy gate stay green. No network
  is introduced (amplitude is local).

## Components / files

- `packages/audio/lib/src/audio_recorder.dart` — add `AudioRecorderHandle`
  interface, `implements` it, `levels()`, `normalizeAmplitude()`.
- `packages/audio/lib/privoice_audio.dart` — export the new symbols.
- `packages/audio/test/amplitude_test.dart` *(new)* — `normalizeAmplitude` tests.
- `apps/mobile/lib/rolling_levels.dart` *(new, pure)* + test.
- `apps/mobile/lib/screens/record_screen.dart` — rewrite (injectable recorder,
  new UI, level subscription).
- `apps/mobile/test/screens/record_screen_test.dart` *(new)* + a
  `FakeAudioRecorderHandle` fake (under `test/fakes/`).

## Out of scope

Pause/resume, audio playback, rename-on-save, waveform persistence, and the R6
(minutes) / R7 (delight) slices.
