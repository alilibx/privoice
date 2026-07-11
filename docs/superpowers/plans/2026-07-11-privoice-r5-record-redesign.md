# R5 — Record Screen Redesign + Live Waveform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the Record screen into the calm-teal language with a live scrolling waveform driven by mic amplitude, keeping the record→transcribe→persist pipeline intact.

**Architecture:** Add an `AudioRecorderHandle` interface + normalized `levels()` stream to the audio package (pure `normalizeAmplitude`), a pure `RollingLevels` FIFO buffer in the app, and rewrite `RecordScreen` to depend on the injectable interface (so tests fake the mic). The screen no longer touches `path_provider` — `AppAudioRecorder.start()` resolves its own output path.

**Tech Stack:** Flutter, `record` 5.2.1 (`onAmplitudeChanged` → `Stream<Amplitude>`, dBFS), path_provider (moved into the audio package), R1 theme tokens.

## Global Constraints

- **Preserve the pipeline verbatim:** `_stopAndTranscribe` still does `ModelLocator.parakeet()` → (null ⇒ "model not found" error) → `transcribeFileInBackground(model, wavPath)` → `Meeting(..., status: MeetingStatus.done)` → `repository.insert` → `Navigator.pop(true)`; failure ⇒ error phase. Keep the existing error copy.
- **Phases:** `idle`, `recording`, `transcribing`, `error` (no `paused` — pause/resume is out of scope).
- **No indefinite/UI-driven animation tickers.** The waveform scroll is driven by the amplitude stream cadence + `setState`, not an `AnimationController`. (The recording `Timer.periodic` elapsed-ticker is real behavior; widget tests must `pump()` — never `pumpAndSettle()` — while recording, and dispose the screen to cancel it.)
- **Privacy:** amplitude is local; introduce no network. Zero-network privacy gate stays green.
- **Theme tokens only**, except the red REC indicator (`scheme.error` is fine) — no arbitrary hex.
- **`RecordScreen` caller compatibility:** `HomeScreen` constructs `RecordScreen(repository: ...)` — the new `recorder` param must be optional with a default.
- **Amplitude mapping:** dBFS (≤ 0) → 0..1 via `normalizeAmplitude(dbfs, {floorDb = -50})` = `((dbfs - floorDb) / -floorDb).clamp(0, 1)`.
- **Commands:**
  ```bash
  export PATH="/opt/homebrew/bin:$HOME/.pub-cache/bin:/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH"
  export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
  export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
  ```
  Package tests: `flutter test` inside the package. Whole-repo analyze: `melos run analyze`.

---

## File Structure

- **Modify** `packages/audio/lib/src/audio_recorder.dart` — add `AudioRecorderHandle`, `normalizeAmplitude`, make `AppAudioRecorder implements AudioRecorderHandle`, `start()` resolves its own docs dir, add `levels()`.
- **Modify** `packages/audio/pubspec.yaml` — add `path_provider` dependency.
- **Create** `packages/audio/test/amplitude_test.dart`.
- **Create** `apps/mobile/lib/rolling_levels.dart` + `apps/mobile/test/rolling_levels_test.dart`.
- **Create** `apps/mobile/test/fakes/fake_audio_recorder.dart`.
- **Rewrite** `apps/mobile/lib/screens/record_screen.dart`.
- **Create** `apps/mobile/test/screens/record_screen_test.dart`.

---

## Task 1: Audio package — recorder interface + amplitude levels

**Files:**
- Modify: `packages/audio/lib/src/audio_recorder.dart`, `packages/audio/pubspec.yaml`
- Test: `packages/audio/test/amplitude_test.dart`

**Interfaces:**
- Consumes: `record` (`AudioRecorder`, `Amplitude`, `onAmplitudeChanged`), `path_provider`.
- Produces:
  - `abstract class AudioRecorderHandle { Future<bool> hasPermission(); Future<void> start(); Future<String> stop(); Future<void> dispose(); Stream<double> levels({Duration interval}); }`
  - `double normalizeAmplitude(double dbfs, {double floorDb})`
  - `class AppAudioRecorder implements AudioRecorderHandle` (unchanged fields + the above).
  All exported via the existing `export 'src/audio_recorder.dart'` in `privoice_audio.dart`.

- [ ] **Step 1: Add path_provider to the audio package**

In `packages/audio/pubspec.yaml`, under `dependencies:` (next to `record`, `path`), add:
```yaml
  path_provider: ^2.1.4
```
Then `cd packages/audio && flutter pub get`.

- [ ] **Step 2: Write the failing test**

Create `packages/audio/test/amplitude_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_audio/privoice_audio.dart';

void main() {
  test('normalizeAmplitude maps dBFS to 0..1', () {
    expect(normalizeAmplitude(0), 1.0);
    expect(normalizeAmplitude(-50), 0.0);
    expect(normalizeAmplitude(-25), closeTo(0.5, 1e-9));
    expect(normalizeAmplitude(-160), 0.0); // clamped below floor
    expect(normalizeAmplitude(10), 1.0); // clamped above 0 dBFS
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd packages/audio && flutter test test/amplitude_test.dart`
Expected: FAIL — `normalizeAmplitude` undefined.

- [ ] **Step 4: Rewrite `audio_recorder.dart`**

Replace the contents of `packages/audio/lib/src/audio_recorder.dart` with:
```dart
import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'recording_config.dart';

/// Clean seam over the platform recorder so screens depend on an interface and
/// tests can fake the microphone.
abstract class AudioRecorderHandle {
  Future<bool> hasPermission();

  /// Begin recording to a fresh file in the app's documents dir.
  Future<void> start();

  /// Stop and return the recorded WAV path.
  Future<String> stop();

  Future<void> dispose();

  /// Normalized 0..1 mic level, sampled every [interval].
  Stream<double> levels({Duration interval});
}

/// dBFS (≤ 0) → 0..1. At/below [floorDb] → 0; 0 dBFS → 1.
double normalizeAmplitude(double dbfs, {double floorDb = -50.0}) {
  return ((dbfs - floorDb) / -floorDb).clamp(0.0, 1.0);
}

/// Records a single meeting to a 16 kHz mono WAV file.
class AppAudioRecorder implements AudioRecorderHandle {
  AppAudioRecorder({RecordingConfig? config})
      : _config = config ?? const RecordingConfig();

  final RecordingConfig _config;
  final AudioRecorder _recorder = AudioRecorder();
  String? _currentPath;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _config.fileName(DateTime.now()));
    _currentPath = path;
    await _recorder.start(_config.toRecordConfig(), path: path);
  }

  @override
  Future<String> stop() async {
    await _recorder.stop();
    final path = _currentPath;
    if (path == null) {
      throw StateError('stop() called before start()');
    }
    return path;
  }

  @override
  Stream<double> levels(
          {Duration interval = const Duration(milliseconds: 150)}) =>
      _recorder
          .onAmplitudeChanged(interval)
          .map((a) => normalizeAmplitude(a.current));

  @override
  Future<void> dispose() => _recorder.dispose();
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd packages/audio && flutter test`
Expected: PASS (amplitude test + the existing `recording_config_test.dart`).

- [ ] **Step 6: Commit**

```bash
git add packages/audio/lib/src/audio_recorder.dart packages/audio/pubspec.yaml packages/audio/test/amplitude_test.dart packages/audio/pubspec.lock
git commit -m "feat(r5): AudioRecorderHandle interface + normalized levels() stream"
```
(If `pubspec.lock` for the package isn't tracked, omit it from the add.)

---

## Task 2: RollingLevels buffer (pure)

**Files:**
- Create: `apps/mobile/lib/rolling_levels.dart`
- Test: `apps/mobile/test/rolling_levels_test.dart`

**Interfaces:**
- Produces: `class RollingLevels { RollingLevels(int capacity); void push(double level); List<double> get samples; }` — fixed-capacity FIFO, oldest first, drops oldest past capacity.

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/rolling_levels_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/rolling_levels.dart';

void main() {
  test('keeps at most capacity samples, oldest dropped, order preserved', () {
    final r = RollingLevels(3);
    expect(r.samples, isEmpty);
    r.push(0.1);
    r.push(0.2);
    expect(r.samples, [0.1, 0.2]);
    r.push(0.3);
    r.push(0.4); // overflows; 0.1 drops
    expect(r.samples, [0.2, 0.3, 0.4]);
    expect(r.samples.length, 3);
  });

  test('samples is not externally mutable', () {
    final r = RollingLevels(2)..push(0.5);
    expect(() => r.samples.add(9), throwsUnsupportedError);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/rolling_levels_test.dart`
Expected: FAIL — `rolling_levels.dart` does not exist.

- [ ] **Step 3: Implement**

Create `apps/mobile/lib/rolling_levels.dart`:
```dart
/// Fixed-capacity FIFO of the most recent normalized mic levels (oldest first).
/// Pushing past [capacity] drops the oldest sample — the model behind the
/// scrolling waveform.
class RollingLevels {
  RollingLevels(this.capacity) : assert(capacity > 0);

  final int capacity;
  final List<double> _buf = [];

  void push(double level) {
    _buf.add(level);
    if (_buf.length > capacity) {
      _buf.removeRange(0, _buf.length - capacity);
    }
  }

  List<double> get samples => List.unmodifiable(_buf);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/rolling_levels_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/rolling_levels.dart apps/mobile/test/rolling_levels_test.dart
git commit -m "feat(r5): RollingLevels FIFO buffer for the scrolling waveform"
```

---

## Task 3: Rewrite RecordScreen (calm-teal + live waveform)

**Files:**
- Rewrite: `apps/mobile/lib/screens/record_screen.dart`
- Create: `apps/mobile/test/fakes/fake_audio_recorder.dart`, `apps/mobile/test/screens/record_screen_test.dart`

**Interfaces:**
- Consumes: `AudioRecorderHandle`/`AppAudioRecorder` (Task 1), `RollingLevels` (Task 2), `ModelLocator` (`../model_paths.dart`), `transcribeFileInBackground` (`privoice_stt`), `Meeting`/`MeetingStatus`.
- Produces: `RecordScreen({super.key, required MeetingRepository repository, AudioRecorderHandle? recorder})`; `_recorder = recorder ?? AppAudioRecorder()`. Record/stop button keyed `Key('recordButton')`; waveform keyed `Key('waveform')`.

- [ ] **Step 1: Write the fake + failing widget tests**

Create `apps/mobile/test/fakes/fake_audio_recorder.dart`:
```dart
import 'dart:async';

import 'package:privoice_audio/privoice_audio.dart';

/// Test double for [AudioRecorderHandle] — no real mic.
class FakeAudioRecorderHandle implements AudioRecorderHandle {
  FakeAudioRecorderHandle({
    this.permission = true,
    this.levelValues = const [0.3, 0.7, 0.5],
  });

  final bool permission;
  final List<double> levelValues;
  bool started = false;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<String> stop() async => '/tmp/fake_meeting.wav';

  @override
  Future<void> dispose() async {}

  @override
  Stream<double> levels({Duration interval = const Duration(milliseconds: 150)}) =>
      Stream<double>.fromIterable(levelValues); // completes; no pending timer
}
```

Create `apps/mobile/test/screens/record_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/record_screen.dart';

import '../fakes/fake_audio_recorder.dart';
import '../fakes/fake_meeting_repository.dart';

void main() {
  testWidgets('idle shows the mic button and start caption', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RecordScreen(
        repository: FakeMeetingRepository(),
        recorder: FakeAudioRecorderHandle(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Tap to start recording'), findsOneWidget);
    expect(find.byKey(const Key('recordButton')), findsOneWidget);
  });

  testWidgets('permission denied shows an error message', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RecordScreen(
        repository: FakeMeetingRepository(),
        recorder: FakeAudioRecorderHandle(permission: false),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recordButton')));
    await tester.pumpAndSettle();
    expect(find.textContaining('permission'), findsOneWidget);
  });

  testWidgets('tapping start enters recording: timer, stop caption, waveform',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RecordScreen(
        repository: FakeMeetingRepository(),
        recorder: FakeAudioRecorderHandle(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recordButton')));
    await tester.pump(); // resolve _start futures → recording phase
    await tester.pump(); // drain the fake level stream

    expect(find.text('Tap to stop & transcribe'), findsOneWidget);
    expect(find.byKey(const Key('waveform')), findsOneWidget);

    // Dispose the screen so the periodic elapsed-ticker is cancelled (no
    // pending-timer failure at test end).
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/mobile && flutter test test/screens/record_screen_test.dart`
Expected: FAIL — `RecordScreen` has no `recorder` param; no `Key('recordButton')`/`Key('waveform')`; captions differ.

- [ ] **Step 3: Rewrite `record_screen.dart`**

Replace the entire contents of `apps/mobile/lib/screens/record_screen.dart` with:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:privoice_audio/privoice_audio.dart';
import 'package:privoice_core/privoice_core.dart';
import 'package:privoice_stt/privoice_stt.dart';

import '../model_paths.dart';
import '../rolling_levels.dart';

enum _Phase { idle, recording, transcribing, error }

const _waveCapacity = 44;

/// Record → (background) transcribe → persist a [Meeting]. Pops `true` when a
/// meeting was saved so the caller can refresh.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, required this.repository, this.recorder});

  final MeetingRepository repository;
  final AudioRecorderHandle? recorder;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  late final AudioRecorderHandle _recorder =
      widget.recorder ?? AppAudioRecorder();
  final Stopwatch _watch = Stopwatch();
  final RollingLevels _levels = RollingLevels(_waveCapacity);
  Timer? _ticker;
  StreamSubscription<double>? _levelSub;

  _Phase _phase = _Phase.idle;
  Duration _elapsed = Duration.zero;
  String _error = '';

  @override
  void dispose() {
    _ticker?.cancel();
    _levelSub?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      setState(() {
        _phase = _Phase.error;
        _error = 'Microphone permission is needed to record.';
      });
      return;
    }
    await _recorder.start();
    _watch
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() => _elapsed = _watch.elapsed);
    });
    _levelSub = _recorder.levels().listen((l) {
      if (mounted) setState(() => _levels.push(l));
    });
    setState(() => _phase = _Phase.recording);
  }

  Future<void> _stopAndTranscribe() async {
    _ticker?.cancel();
    await _levelSub?.cancel();
    _watch.stop();
    final durationMs = _watch.elapsedMilliseconds;
    final wavPath = await _recorder.stop();
    setState(() => _phase = _Phase.transcribing);

    try {
      final model = await ModelLocator.parakeet();
      if (model == null) {
        setState(() {
          _phase = _Phase.error;
          _error =
              'Speech model not found on device.\nPush it to the app files dir, '
              'or wait for the in-app download (coming soon).';
        });
        return;
      }

      final transcript = await transcribeFileInBackground(model, wavPath);

      final meeting = Meeting(
        title: _defaultTitle(),
        createdAt: DateTime.now(),
        audioPath: wavPath,
        durationMs: durationMs,
        transcript: transcript.fullText,
        status: MeetingStatus.done,
      );
      await widget.repository.insert(meeting);

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _phase = _Phase.error;
        _error = 'Transcription failed: $e';
      });
    }
  }

  String _defaultTitle() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    return 'Meeting ${now.day}/${now.month} $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recording = _phase == _Phase.recording;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: recording
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: scheme.error, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text('REC',
                      style: TextStyle(
                          color: scheme.error,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          letterSpacing: 0.5)),
                ],
              )
            : const Text('New recording'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _phase == _Phase.transcribing
              ? null
              : () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: _body(scheme)),
      ),
    );
  }

  Widget _body(ColorScheme scheme) {
    switch (_phase) {
      case _Phase.transcribing:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                  color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(Icons.auto_awesome,
                  size: 34, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 22),
            Text('Transcribing…',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            SizedBox(
              width: 180,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: const LinearProgressIndicator(minHeight: 5),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Running on your phone — nothing is uploaded.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        );
      case _Phase.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 16),
            Text(_error, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Back'),
            ),
          ],
        );
      case _Phase.idle:
      case _Phase.recording:
        final recording = _phase == _Phase.recording;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _fmt(_elapsed),
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w300,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: recording ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 36),
            _Waveform(
              key: const Key('waveform'),
              samples: _levels.samples,
              capacity: _waveCapacity,
              active: recording,
            ),
            const SizedBox(height: 40),
            _RecordButton(
              key: const Key('recordButton'),
              recording: recording,
              onTap: recording ? _stopAndTranscribe : _start,
            ),
            const SizedBox(height: 24),
            Text(
              recording ? 'Tap to stop & transcribe' : 'Tap to start recording',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        );
    }
  }
}

/// Right-aligned scrolling bars: newest sample at the right, older bars fade.
class _Waveform extends StatelessWidget {
  const _Waveform({
    super.key,
    required this.samples,
    required this.capacity,
    required this.active,
  });

  final List<double> samples;
  final int capacity;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recent = samples.length > capacity
        ? samples.sublist(samples.length - capacity)
        : samples;
    final values = <double>[
      ...List<double>.filled(capacity - recent.length, 0.0),
      ...recent,
    ];
    const maxH = 84.0;
    return SizedBox(
      height: maxH,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < values.length; i++)
            Container(
              width: 3,
              height: 3 + values[i] * (maxH - 3),
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: scheme.primary
                    .withValues(alpha: active ? 0.25 + 0.75 * (i / capacity) : 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({super.key, required this.recording, required this.onTap});

  final bool recording;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: 92,
        height: 92,
        decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
        child: recording
            ? Center(
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: scheme.onPrimary,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              )
            : Icon(Icons.mic_rounded, size: 42, color: scheme.onPrimary),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the Record tests to verify they pass**

Run: `cd apps/mobile && flutter test test/screens/record_screen_test.dart`
Expected: PASS (3 tests), no pending-timer failure.

- [ ] **Step 5: Analyze changed files**

Run: `cd apps/mobile && flutter analyze lib/screens/record_screen.dart lib/rolling_levels.dart test/screens/record_screen_test.dart test/fakes/fake_audio_recorder.dart`
Expected: "No issues found!" Fix any unused import (e.g. the old `path_provider` import must be gone) before continuing.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/screens/record_screen.dart apps/mobile/test/screens/record_screen_test.dart apps/mobile/test/fakes/fake_audio_recorder.dart
git commit -m "feat(r5): redesign Record screen with live scrolling waveform"
```

---

## Task 4: Full verification + STATUS + device build

**Files:**
- Modify: `STATUS.md`

**Interfaces:** none.

- [ ] **Step 1: Whole-repo analyze**

Run:
```bash
export PATH="/opt/homebrew/bin:$HOME/.pub-cache/bin:/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH"
export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
melos run analyze
```
Expected: "No issues found!" for all 6 packages.

- [ ] **Step 2: Mobile + audio suites**

Run: `cd apps/mobile && flutter test` then `cd packages/audio && flutter test`
Expected: all PASS, no hang. (Do NOT run the aggregate `melos run test` — `privoice_models` has no test dir and fails it; that's a known separate gap.)

- [ ] **Step 3: Debug build**

Run: `cd apps/mobile && flutter build apk --debug`
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`.

- [ ] **Step 4: Update STATUS.md**

Edit `STATUS.md`:
- Redesign line: flip `R5 record ⬜` to `R5 record ✅ (code-complete; on-device pending)` with note: "calm-teal Record screen + live scrolling waveform (mic amplitude via AudioRecorderHandle.levels); injectable recorder for tests". Change "Next: R5 record" → "Next: R6 minutes".
- `Now:` line: add R5.
- Feature checklist: move "live audio level meter" from Todo to Working (note: as a scrolling waveform).
- Bump **Last updated** to `2026-07-11`.

- [ ] **Step 5: Commit**

```bash
git add STATUS.md
git commit -m "docs(status): R5 Record redesign + live waveform done (code-complete)"
```

---

## Self-Review Notes

- **Spec coverage:** `AudioRecorderHandle` + `levels()` + `normalizeAmplitude` (Task 1) · `RollingLevels` (Task 2) · injectable recorder + calm-teal UI + scrolling waveform + preserved pipeline + REC/transcribing/error states + level subscription lifecycle (Task 3) · tests at each layer + regression (Tasks 1–4). All covered.
- **Type consistency:** `AudioRecorderHandle` methods (`hasPermission`/`start()`/`stop()`/`dispose()`/`levels({interval})`), `normalizeAmplitude(dbfs,{floorDb})`, `RollingLevels(capacity)/push/samples`, `RecordScreen({repository, recorder})`, `FakeAudioRecorderHandle({permission, levelValues})`, `Key('recordButton')`/`Key('waveform')` used consistently across tasks.
- **Placeholder scan:** none — every step has complete code.
- **Deliberate refinement vs spec:** `start()` takes no arg (docs-dir resolution moved into `AppAudioRecorder`) so the screen has no `path_provider` dependency to mock — improves testability; spec's intent (injectable, fakeable recorder) is preserved.
