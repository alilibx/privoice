# Privoice S0–S1: Toolchain Bootstrap + STT Spike — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Privoice Flutter monorepo and prove on-device speech-to-text works on a real Android phone, capturing the performance numbers (RTF, RAM, model size, thermal feel) that the research could not verify.

**Architecture:** A melos-managed Dart/Flutter monorepo. A tiny spike app in `apps/mobile` records 16 kHz mono WAV via the `audio` package and transcribes it via the `stt` package, which wraps the official `sherpa_onnx` Dart binding running NVIDIA Parakeet-TDT v3 INT8. All binding-specific code is isolated behind clean Dart interfaces so later online/iOS backends slot in without touching the UI. The spike ends with a written go/no-go benchmark report.

**Tech Stack:** Flutter (stable), Dart, melos, `record` (audio capture), `sherpa_onnx` (STT), `drift` (later), Android SDK, JDK 17.

## Global Constraints

- **Framework:** Flutter stable channel only. Single Dart codebase; **no hand-authored native app code** in S0–S1.
- **First platform:** Android. iOS is not built or tested in this plan.
- **JDK:** Temurin/OpenJDK **17** (required by current Android Gradle Plugin).
- **Android:** `compileSdk 35`, `minSdk 24`, `targetSdk 35`. NDK version per the `sherpa_onnx` package requirement.
- **Audio format:** 16 kHz, mono, 16-bit PCM WAV — Parakeet/Whisper input format. Non-negotiable across the pipeline.
- **Monorepo tooling:** melos workspace. `apps/*` depend on `packages/*`; packages never depend on the app.
- **Package boundaries:** all `sherpa_onnx` calls live only in `packages/stt`; all `record` calls live only in `packages/audio`. UI touches neither directly — only their public interfaces.
- **Privacy invariant:** the spike must run fully offline (airplane mode) once the model file is on the device. No network calls at transcription time.
- **Model:** `sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8`, obtained from the `sherpa_onnx` model releases; pushed to the device (not bundled in the APK).
- **Commits:** conventional-commit messages; commit at the end of each task.

> **Binding-API note:** The `sherpa_onnx` and `record` code below is written against those packages' documented public APIs. Pin the versions in Task 1, then, if a pinned version's API differs, adapt to that version's own `example/` — but keep the *interface* (`SttEngine`, `Transcript`) defined here unchanged.

---

## Task 0: Toolchain bootstrap

**Files:**
- Create: `tools/bootstrap-macos.md` (record of the exact steps run, for teammates)

**Interfaces:**
- Produces: a working `flutter` + Android toolchain. Later tasks assume `flutter`, `dart`, `adb`, `sdkmanager`, and a JDK 17 are on `PATH` and `flutter doctor` passes for Android.

- [ ] **Step 1: Verify current state (expected: mostly missing)**

Run:
```bash
flutter --version 2>/dev/null || echo "flutter: NOT FOUND"
java -version 2>&1 | head -1
ls "$HOME/Library/Android/sdk" 2>/dev/null || echo "android sdk: NOT FOUND"
```
Expected: `flutter: NOT FOUND`, no Java runtime, android sdk not found. (Xcode 26.5 is already present but unused in this plan.)

- [ ] **Step 2: Install JDK 17 and Flutter via Homebrew**

Run:
```bash
brew install --cask temurin@17
brew install --cask flutter
```
Expected: both casks install. If `brew` is absent, install it first from https://brew.sh, then re-run.

- [ ] **Step 3: Install Android command-line tools + SDK packages**

Run:
```bash
brew install --cask android-commandlinetools
yes | sdkmanager --install "platform-tools" "platforms;android-35" "build-tools;35.0.0"
yes | sdkmanager --licenses
```
Expected: packages install; all licenses accepted. `adb` now resolves (`adb version`).

- [ ] **Step 4: Point Flutter at the JDK and SDK, then run doctor**

Run:
```bash
flutter config --jdk-dir="$(/usr/libexec/java_home -v 17)"
flutter config --android-sdk "$(dirname "$(dirname "$(command -v sdkmanager)")")"
flutter doctor -v
```
Expected: "Flutter" and "Android toolchain" checks show `[✓]`. iOS/Chrome checks may be `[!]` — acceptable, out of scope.

- [ ] **Step 5: Confirm a device or emulator is available**

Run:
```bash
flutter devices
```
Expected: at least one Android target listed (physical device via USB with developer mode + USB debugging, or an emulator started via `flutter emulators --launch <id>`). If none, connect a phone or create an emulator before continuing.

- [ ] **Step 6: Write down what was done and commit**

Create `tools/bootstrap-macos.md` documenting the exact commands run and the resulting `flutter doctor` summary. Then:
```bash
cd /Users/ali/Development/me/apps/privoice
git init
git add tools/bootstrap-macos.md docs/
git commit -m "chore: document toolchain bootstrap and add design/plan docs"
```
Expected: first commit created (the design + this plan under `docs/` come along).

---

## Task 1: Monorepo scaffold (melos workspace + package skeleton)

**Files:**
- Create: `melos.yaml`
- Create: `pubspec.yaml` (workspace root)
- Create: `analysis_options.yaml`
- Create: `.gitignore`
- Create: `apps/mobile/` (via `flutter create`)
- Create: `packages/core/`, `packages/audio/`, `packages/stt/` (via `flutter create --template=package`)

**Interfaces:**
- Produces: `melos bootstrap` wires all packages; `melos run analyze` runs `flutter analyze` across the workspace with zero issues. Package names: `privoice_core`, `privoice_audio`, `privoice_stt`, app package `mobile`.

- [ ] **Step 1: Activate melos**

Run:
```bash
dart pub global activate melos
export PATH="$PATH":"$HOME/.pub-cache/bin"
melos --version
```
Expected: melos version prints.

- [ ] **Step 2: Create the app and packages**

Run:
```bash
cd /Users/ali/Development/me/apps/privoice
flutter create --org com.privoice --project-name mobile --platforms=android apps/mobile
flutter create --template=package packages/core
flutter create --template=package packages/audio
flutter create --template=package packages/stt
```
Expected: four Flutter/Dart packages scaffolded.

- [ ] **Step 3: Rename packages and set the Android build config**

Set `name:` in each package's `pubspec.yaml` to `privoice_core`, `privoice_audio`, `privoice_stt` respectively. In `apps/mobile/android/app/build.gradle` (or `build.gradle.kts`), set `compileSdk 35`, `minSdk 24`, `targetSdk 35`.

- [ ] **Step 4: Create `melos.yaml`**

```yaml
name: privoice
packages:
  - apps/**
  - packages/**

scripts:
  analyze:
    exec: flutter analyze
    description: Analyze all packages
  test:
    exec: flutter test
    description: Test all packages that have tests
```

- [ ] **Step 5: Create root `pubspec.yaml`**

```yaml
name: privoice_workspace
environment:
  sdk: ">=3.4.0 <4.0.0"
dev_dependencies:
  melos: ^6.0.0
```

- [ ] **Step 6: Create shared `analysis_options.yaml`**

```yaml
include: package:flutter_lints/flutter.yaml
linter:
  rules:
    prefer_final_locals: true
    avoid_print: false # spike logs to console; tighten later
```
Reference this file from each package's own `analysis_options.yaml` via `include: ../../analysis_options.yaml`.

- [ ] **Step 7: Create `.gitignore`**

```gitignore
.dart_tool/
.packages
build/
*.iml
.idea/
.gradle/
local.properties
**/models/*.onnx
**/models/*.bin
*.wav
```

- [ ] **Step 8: Bootstrap and analyze**

Run:
```bash
melos bootstrap
melos run analyze
```
Expected: bootstrap links packages; analyze reports "No issues found!" across all packages.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "chore: scaffold melos monorepo with mobile app and core/audio/stt packages"
```

---

## Task 2: `audio` package — 16 kHz mono WAV recording

**Files:**
- Create: `packages/audio/lib/privoice_audio.dart`
- Create: `packages/audio/lib/src/recording_config.dart`
- Create: `packages/audio/lib/src/audio_recorder.dart`
- Test: `packages/audio/test/recording_config_test.dart`
- Modify: `packages/audio/pubspec.yaml` (add `record`)

**Interfaces:**
- Produces:
  - `class RecordingConfig` with `const RecordingConfig()` defaulting to `sampleRate = 16000`, `numChannels = 1`, `encoder = AudioEncoder.wav`, and `String fileName(DateTime now)` returning `meeting_<epochMs>.wav`.
  - `class AppAudioRecorder` with `Future<void> start(String dirPath)`, `Future<String> stop()` (returns the WAV path), `Future<bool> hasPermission()`.

- [ ] **Step 1: Add the `record` dependency**

In `packages/audio/pubspec.yaml` add under `dependencies:`:
```yaml
  record: ^5.1.0
  path: ^1.9.0
```
Run: `cd packages/audio && flutter pub get` — expected: resolves.

- [ ] **Step 2: Write the failing test for `RecordingConfig`**

`packages/audio/test/recording_config_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_audio/privoice_audio.dart';

void main() {
  test('defaults to 16kHz mono wav', () {
    const cfg = RecordingConfig();
    expect(cfg.sampleRate, 16000);
    expect(cfg.numChannels, 1);
  });

  test('fileName is deterministic from timestamp', () {
    const cfg = RecordingConfig();
    final name = cfg.fileName(DateTime.fromMillisecondsSinceEpoch(1720000000000));
    expect(name, 'meeting_1720000000000.wav');
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/recording_config_test.dart`
Expected: FAIL — `RecordingConfig` / `privoice_audio.dart` not defined.

- [ ] **Step 4: Implement `RecordingConfig`**

`packages/audio/lib/src/recording_config.dart`:
```dart
import 'package:record/record.dart';

class RecordingConfig {
  const RecordingConfig({
    this.sampleRate = 16000,
    this.numChannels = 1,
    this.encoder = AudioEncoder.wav,
  });

  final int sampleRate;
  final int numChannels;
  final AudioEncoder encoder;

  String fileName(DateTime now) => 'meeting_${now.millisecondsSinceEpoch}.wav';

  RecordConfig toRecordConfig() => RecordConfig(
        encoder: encoder,
        sampleRate: sampleRate,
        numChannels: numChannels,
      );
}
```

- [ ] **Step 5: Implement `AppAudioRecorder` and the barrel file**

`packages/audio/lib/src/audio_recorder.dart`:
```dart
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'recording_config.dart';

class AppAudioRecorder {
  AppAudioRecorder({RecordingConfig? config})
      : _config = config ?? const RecordingConfig();

  final RecordingConfig _config;
  final AudioRecorder _recorder = AudioRecorder();
  String? _currentPath;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start(String dirPath) async {
    final path = p.join(dirPath, _config.fileName(DateTime.now()));
    _currentPath = path;
    await _recorder.start(_config.toRecordConfig(), path: path);
  }

  Future<String> stop() async {
    await _recorder.stop();
    final path = _currentPath;
    if (path == null) {
      throw StateError('stop() called before start()');
    }
    return path;
  }

  Future<void> dispose() => _recorder.dispose();
}
```

`packages/audio/lib/privoice_audio.dart`:
```dart
export 'src/recording_config.dart';
export 'src/audio_recorder.dart';
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test test/recording_config_test.dart`
Expected: PASS (both tests).

- [ ] **Step 7: Add RECORD_AUDIO permission to the app manifest**

In `apps/mobile/android/app/src/main/AndroidManifest.xml`, add inside `<manifest>` (above `<application>`):
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

- [ ] **Step 8: Commit**

```bash
git add packages/audio apps/mobile/android/app/src/main/AndroidManifest.xml
git commit -m "feat(audio): add 16kHz mono WAV recorder with config"
```

---

## Task 3: `stt` package — sherpa-onnx transcription behind a clean interface

**Files:**
- Create: `packages/stt/lib/privoice_stt.dart`
- Create: `packages/stt/lib/src/transcript.dart`
- Create: `packages/stt/lib/src/stt_engine.dart` (abstract interface)
- Create: `packages/stt/lib/src/sherpa_stt_engine.dart` (implementation)
- Test: `packages/stt/test/transcript_test.dart`
- Modify: `packages/stt/pubspec.yaml` (add `sherpa_onnx`)

**Interfaces:**
- Produces:
  - `class TranscriptSegment { final String text; final double startSec; final double endSec; }`
  - `class Transcript { final List<TranscriptSegment> segments; final String fullText; final Duration audioDuration; }` with `Transcript.fromSegments(...)` computing `fullText` by joining segment texts with a space.
  - `abstract class SttEngine { Future<void> init(SttModelPaths paths); Future<Transcript> transcribe(String wavPath); Future<void> dispose(); }`
  - `class SttModelPaths { final String encoder, decoder, joiner, tokens; }` (Parakeet transducer layout).
  - `class SherpaSttEngine implements SttEngine` — the only file that imports `sherpa_onnx`.
- Consumes: nothing from earlier tasks (independent package).

- [ ] **Step 1: Write the failing test for `Transcript`**

`packages/stt/test/transcript_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_stt/privoice_stt.dart';

void main() {
  test('fromSegments joins text with spaces and keeps duration', () {
    final t = Transcript.fromSegments(
      const [
        TranscriptSegment(text: 'hello', startSec: 0.0, endSec: 1.0),
        TranscriptSegment(text: 'world', startSec: 1.0, endSec: 2.0),
      ],
      const Duration(seconds: 2),
    );
    expect(t.fullText, 'hello world');
    expect(t.segments.length, 2);
    expect(t.audioDuration, const Duration(seconds: 2));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/stt && flutter test test/transcript_test.dart`
Expected: FAIL — `Transcript` not defined.

- [ ] **Step 3: Implement the transcript model + interface**

`packages/stt/lib/src/transcript.dart`:
```dart
class TranscriptSegment {
  const TranscriptSegment({
    required this.text,
    required this.startSec,
    required this.endSec,
  });
  final String text;
  final double startSec;
  final double endSec;
}

class Transcript {
  const Transcript({
    required this.segments,
    required this.fullText,
    required this.audioDuration,
  });

  final List<TranscriptSegment> segments;
  final String fullText;
  final Duration audioDuration;

  factory Transcript.fromSegments(
    List<TranscriptSegment> segments,
    Duration audioDuration,
  ) {
    final text = segments.map((s) => s.text.trim()).where((s) => s.isNotEmpty).join(' ');
    return Transcript(
      segments: segments,
      fullText: text,
      audioDuration: audioDuration,
    );
  }
}
```

`packages/stt/lib/src/stt_engine.dart`:
```dart
import 'transcript.dart';

class SttModelPaths {
  const SttModelPaths({
    required this.encoder,
    required this.decoder,
    required this.joiner,
    required this.tokens,
  });
  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;
}

abstract class SttEngine {
  Future<void> init(SttModelPaths paths);
  Future<Transcript> transcribe(String wavPath);
  Future<void> dispose();
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/transcript_test.dart`
Expected: PASS.

- [ ] **Step 5: Add the `sherpa_onnx` dependency**

In `packages/stt/lib/privoice_stt.dart`:
```dart
export 'src/transcript.dart';
export 'src/stt_engine.dart';
export 'src/sherpa_stt_engine.dart';
```
In `packages/stt/pubspec.yaml` add under `dependencies:`:
```yaml
  sherpa_onnx: ^1.10.0   # pin to the latest 1.x on pub.dev; note the exact version in the commit
```
Run: `flutter pub get` — expected: resolves. Record the exact resolved version.

- [ ] **Step 6: Implement `SherpaSttEngine` (Parakeet transducer, offline)**

`packages/stt/lib/src/sherpa_stt_engine.dart`. Written against the `sherpa_onnx` Dart `OfflineRecognizer` API (transducer config for Parakeet). If the pinned version's field names differ, reconcile against that version's `example/offline-recognizer`, keeping the `SttEngine` interface intact:
```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'transcript.dart';
import 'stt_engine.dart';

class SherpaSttEngine implements SttEngine {
  sherpa.OfflineRecognizer? _recognizer;

  @override
  Future<void> init(SttModelPaths paths) async {
    sherpa.initBindings();
    final modelConfig = sherpa.OfflineModelConfig(
      transducer: sherpa.OfflineTransducerModelConfig(
        encoder: paths.encoder,
        decoder: paths.decoder,
        joiner: paths.joiner,
      ),
      tokens: paths.tokens,
      modelType: 'nemo_transducer',
      numThreads: 2,
      debug: false,
    );
    final config = sherpa.OfflineRecognizerConfig(model: modelConfig);
    _recognizer = sherpa.OfflineRecognizer(config);
  }

  @override
  Future<Transcript> transcribe(String wavPath) async {
    final rec = _recognizer;
    if (rec == null) throw StateError('init() must be called before transcribe()');

    final wave = sherpa.readWave(wavPath); // returns samples + sampleRate
    final stream = rec.createStream();
    stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
    rec.decode(stream);
    final result = rec.getResult(stream);
    stream.free();

    final durationSec = wave.samples.length / wave.sampleRate;
    final segment = TranscriptSegment(
      text: result.text,
      startSec: 0.0,
      endSec: durationSec,
    );
    return Transcript.fromSegments(
      [segment],
      Duration(milliseconds: (durationSec * 1000).round()),
    );
  }

  @override
  Future<void> dispose() async {
    _recognizer?.free();
    _recognizer = null;
  }
}
```
> Segment-level timestamps are collapsed to a single segment in S1 (spike only needs text + duration). Fine-grained segments/diarization come in a later plan.

- [ ] **Step 7: Analyze the package**

Run: `flutter analyze`
Expected: "No issues found!" (If the binding API required renames, they are contained to this one file.)

- [ ] **Step 8: Commit**

```bash
git add packages/stt
git commit -m "feat(stt): add Transcript model and sherpa-onnx Parakeet engine behind SttEngine interface"
```

---

## Task 4: Spike screen — record → transcribe → measure

**Files:**
- Create: `apps/mobile/lib/spike_screen.dart`
- Create: `apps/mobile/lib/benchmark.dart`
- Modify: `apps/mobile/lib/main.dart`
- Modify: `apps/mobile/pubspec.yaml` (path-depend on the three packages + `path_provider`)
- Test: `apps/mobile/test/benchmark_test.dart`

**Interfaces:**
- Consumes: `AppAudioRecorder` (Task 2); `SherpaSttEngine`, `SttModelPaths`, `Transcript` (Task 3).
- Produces: `class BenchmarkResult { final double rtf; final int audioMs; final int transcribeMs; }` with `BenchmarkResult.compute(audioMs, transcribeMs)` where `rtf = transcribeMs / audioMs`, and `String describe()` returning a one-line summary. This is the number we gate on.

- [ ] **Step 1: Wire package dependencies**

In `apps/mobile/pubspec.yaml` under `dependencies:`:
```yaml
  privoice_audio:
    path: ../../packages/audio
  privoice_stt:
    path: ../../packages/stt
  path_provider: ^2.1.0
```
Run: `cd apps/mobile && flutter pub get` — expected: resolves.

- [ ] **Step 2: Write the failing test for `BenchmarkResult`**

`apps/mobile/test/benchmark_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/benchmark.dart';

void main() {
  test('rtf is transcribe time over audio time', () {
    final r = BenchmarkResult.compute(audioMs: 10000, transcribeMs: 2500);
    expect(r.rtf, 0.25);
  });

  test('describe includes rtf and is faster-than-realtime flagged', () {
    final r = BenchmarkResult.compute(audioMs: 10000, transcribeMs: 2500);
    expect(r.describe(), contains('0.25'));
    expect(r.describe(), contains('faster than realtime'));
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/benchmark_test.dart`
Expected: FAIL — `benchmark.dart` not defined.

- [ ] **Step 4: Implement `BenchmarkResult`**

`apps/mobile/lib/benchmark.dart`:
```dart
class BenchmarkResult {
  const BenchmarkResult({
    required this.rtf,
    required this.audioMs,
    required this.transcribeMs,
  });

  final double rtf;
  final int audioMs;
  final int transcribeMs;

  factory BenchmarkResult.compute({
    required int audioMs,
    required int transcribeMs,
  }) {
    return BenchmarkResult(
      rtf: transcribeMs / audioMs,
      audioMs: audioMs,
      transcribeMs: transcribeMs,
    );
  }

  String describe() {
    final speed = rtf < 1.0 ? 'faster than realtime' : 'SLOWER than realtime';
    return 'RTF=${rtf.toStringAsFixed(2)} ($speed) | '
        'audio=${audioMs}ms transcribe=${transcribeMs}ms';
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/benchmark_test.dart`
Expected: PASS (both tests).

- [ ] **Step 6: Build the spike screen**

`apps/mobile/lib/spike_screen.dart`:
```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:privoice_audio/privoice_audio.dart';
import 'package:privoice_stt/privoice_stt.dart';
import 'benchmark.dart';

class SpikeScreen extends StatefulWidget {
  const SpikeScreen({super.key});
  @override
  State<SpikeScreen> createState() => _SpikeScreenState();
}

class _SpikeScreenState extends State<SpikeScreen> {
  final _recorder = AppAudioRecorder();
  final _stt = SherpaSttEngine();
  bool _recording = false;
  bool _busy = false;
  String _status = 'Idle';
  String _transcript = '';
  String _bench = '';

  Future<String> _modelDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'models', 'parakeet-tdt-v3-int8');
  }

  Future<void> _ensureInit() async {
    final m = await _modelDir();
    await _stt.init(SttModelPaths(
      encoder: p.join(m, 'encoder.int8.onnx'),
      decoder: p.join(m, 'decoder.int8.onnx'),
      joiner: p.join(m, 'joiner.int8.onnx'),
      tokens: p.join(m, 'tokens.txt'),
    ));
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      final path = await _recorder.stop();
      setState(() { _recording = false; _busy = true; _status = 'Transcribing...'; });
      await _transcribe(path);
    } else {
      if (!await _recorder.hasPermission()) {
        setState(() => _status = 'Microphone permission denied');
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      await _recorder.start(dir.path);
      setState(() { _recording = true; _status = 'Recording...'; });
    }
  }

  Future<void> _transcribe(String wavPath) async {
    try {
      await _ensureInit();
      final sw = Stopwatch()..start();
      final t = await _stt.transcribe(wavPath);
      sw.stop();
      final bench = BenchmarkResult.compute(
        audioMs: t.audioDuration.inMilliseconds,
        transcribeMs: sw.elapsedMilliseconds,
      );
      final modelBytes = await _dirSize(await _modelDir());
      setState(() {
        _transcript = t.fullText;
        _bench = '${bench.describe()} | model=${(modelBytes / 1e6).toStringAsFixed(0)}MB';
        _status = 'Done';
        _busy = false;
      });
      // Also print for `flutter logs` capture.
      // ignore: avoid_print
      print('SPIKE_BENCH ${bench.describe()} model=${modelBytes}B');
    } catch (e) {
      setState(() { _status = 'Error: $e'; _busy = false; });
    }
  }

  Future<int> _dirSize(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list(recursive: true)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privoice STT Spike')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: $_status'),
            const SizedBox(height: 8),
            if (_bench.isNotEmpty)
              Text(_bench, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(child: SingleChildScrollView(child: Text(_transcript))),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _toggleRecord,
              child: Text(_recording ? 'Stop & Transcribe' : 'Record'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Point `main.dart` at the spike screen**

`apps/mobile/lib/main.dart`:
```dart
import 'package:flutter/material.dart';
import 'spike_screen.dart';

void main() => runApp(const PrivoiceApp());

class PrivoiceApp extends StatelessWidget {
  const PrivoiceApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Privoice',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const SpikeScreen(),
    );
  }
}
```

- [ ] **Step 8: Analyze and commit**

Run: `flutter analyze`
Expected: "No issues found!"
```bash
git add apps/mobile
git commit -m "feat(spike): record-transcribe-measure screen with benchmark output"
```

---

## Task 5: Get the model onto the device and run the spike

**Files:**
- Create: `tools/fetch-and-push-model.sh`
- Create: `docs/superpowers/benchmarks/2026-07-09-stt-spike-results.md`

**Interfaces:**
- Consumes: the running app from Task 4.
- Produces: the go/no-go benchmark report. This is the deliverable that decides whether we proceed to S2–S4 as planned or change the model.

- [ ] **Step 1: Write the model fetch+push script**

`tools/fetch-and-push-model.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
# Downloads the Parakeet-TDT v3 INT8 model bundle from the sherpa-onnx model
# releases and pushes it into the app's documents dir on a connected device.
# Model tarball name/URL: confirm the exact asset on
#   https://github.com/k2-fsa/sherpa-onnx/releases (tag: asr-models)
MODEL="sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"
URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${MODEL}.tar.bz2"
APP_ID="com.privoice.mobile"

work="$(mktemp -d)"
curl -L "$URL" -o "$work/model.tar.bz2"
tar xjf "$work/model.tar.bz2" -C "$work"

# App documents dir on Android maps to /data/data/<app>/app_flutter via run-as,
# but for a debug build the simplest reliable path is external files dir:
DEST="/sdcard/Android/data/${APP_ID}/files/models/parakeet-tdt-v3-int8"
adb shell mkdir -p "$DEST"
for f in encoder.int8.onnx decoder.int8.onnx joiner.int8.onnx tokens.txt; do
  adb push "$work/$MODEL/$f" "$DEST/$f"
done
echo "Pushed model to $DEST"
```
> The app reads from `getApplicationDocumentsDirectory()`. On Android that is the app-private files dir; adjust the spike's `_modelDir()` to use `getExternalStorageDirectory()` if you push to the external path above, so the script destination and the app read path match. Pick ONE location and make both sides agree before running.

- [ ] **Step 2: Make the model path consistent, then run the app**

Ensure `spike_screen.dart` `_modelDir()` and `tools/fetch-and-push-model.sh` `DEST` resolve to the same directory (use `getExternalStorageDirectory()` for `/sdcard/Android/data/.../files`). Then:
```bash
chmod +x tools/fetch-and-push-model.sh
cd apps/mobile && flutter run --release   # release for realistic perf numbers
```
Expected: app launches on the device showing the spike screen.

- [ ] **Step 3: Push the model**

In a second terminal:
```bash
./tools/fetch-and-push-model.sh
```
Expected: four files pushed; "Pushed model to ..." printed.

- [ ] **Step 4: Run the measured spike**

On the device: tap **Record**, speak (or play meeting audio) for ~30–60 s, tap **Stop & Transcribe**. Then capture logs:
```bash
flutter logs | grep SPIKE_BENCH
```
Expected: a transcript on screen and a `SPIKE_BENCH RTF=... model=...B` line. Note peak RAM from Android Studio Profiler or `adb shell dumpsys meminfo com.privoice.mobile`. Note whether the phone got warm.

- [ ] **Step 5: Write the go/no-go report**

`docs/superpowers/benchmarks/2026-07-09-stt-spike-results.md` with: device model, Android version, resolved `sherpa_onnx` version, model, measured **RTF**, **peak RAM (MB)**, **model size on disk (MB)**, transcript accuracy impression on real speech, thermal feel, and a **VERDICT: GO / ADJUST**. If ADJUST, note the next model to try (e.g., whisper.cpp base via sherpa-onnx, or a smaller Parakeet/Whisper).

- [ ] **Step 6: Commit**

```bash
git add tools/fetch-and-push-model.sh docs/superpowers/benchmarks/
git commit -m "chore(spike): add model fetch script and STT benchmark results"
```

---

## Definition of done (S0–S1)

- `flutter doctor` green for Android; monorepo bootstraps and analyzes clean.
- `melos run test` passes (audio, stt, mobile unit tests).
- On a real Android phone, in **airplane mode**, you record speech and see a transcript.
- A written benchmark report exists with RTF / RAM / model-size numbers and an explicit GO or ADJUST verdict.

## Self-review notes

- **Spec coverage:** S0 (Task 0–1), S1 spike + measurement of all five §2 open questions (Task 4–5), package boundaries enforced (audio/stt isolation), offline invariant (Task 5 Step 4). Device tiering, diarization, LLM, export are correctly **absent** — they belong to later plans.
- **Interface consistency:** `SttEngine.init/transcribe/dispose`, `Transcript.fromSegments`, `SttModelPaths{encoder,decoder,joiner,tokens}`, `BenchmarkResult.compute({audioMs,transcribeMs})` are used identically wherever referenced.
- **Known soft spot:** exact `sherpa_onnx` field names and the release asset URL must be reconciled against the pinned version / releases page at execution time — flagged inline at Task 3 Step 6 and Task 5 Step 1. Interfaces are designed so any such change is contained to one file.
