# Audio Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user import an existing recording — including a Zoom/Teams `.mp4` — and run it through the existing transcribe → minutes pipeline, at any file length.

**Architecture:** A native transcoder behind `AudioImporter` converts any container to 16 kHz mono 16-bit WAV. A pure-Dart `WavReader` reads bounded windows through `RandomAccessFile` so no file is ever fully in memory, and `ChunkPlanner` places ~5-minute cuts at the quietest nearby point. `transcribeFileInBackground` iterates those chunks inside its existing `compute` isolate and reports progress, becoming the single transcription path for both recording and import.

**Tech Stack:** Flutter 3.44.5 / Dart 3.12.2, Melos monorepo, `audio_decoder` 0.8.1, `file_picker` 11.0.2, `sherpa_onnx` 1.13.4, `flutter_test`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-28-audio-import-design.md`. Read it before Task 1.
- Output format is exactly **16 kHz, mono, 16-bit PCM WAV**. `WavReader` rejects anything else.
- Tuning constants, exact values: `targetChunkSeconds = 300`, `snapWindowSeconds = 10`, `rmsFrameMs = 20`.
- `packages/stt` and `packages/audio` must not import `flutter/material.dart`. `WavReader` and `ChunkPlanner` must be **pure Dart** (`dart:io`, `dart:typed_data`, `dart:math` only) so they test without a widget harness.
- **No file is ever read whole.** Any code path that loads a complete audio file into memory is a defect — that is the entire point of this slice.
- Chunks must **partition** the audio: contiguous, non-overlapping, summing exactly to `sampleCount`. No overlap, therefore no text dedupe.
- Dependency versions are already verified to resolve with zero downgrades: `audio_decoder 0.8.1`, `file_picker 11.0.2`. If `pub add` wants to change any *other* package's version, stop and report it.
- Conventional Commits. Branch `feat/audio-import` (already created and checked out).
- Environment: `export PATH="/opt/homebrew/bin:$HOME/.pub-cache/bin:$PATH"` first.
- Gate every task: `melos run analyze` clean AND `melos run test` green. The existing suite (155 tests) must stay green — the record-flow tests are the safety net for unifying the transcription path.
- User-facing copy is fixed by this plan. Use the exact strings; do not paraphrase.

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `packages/stt/lib/src/wav_reader.dart` | Create | RIFF parsing + validation + windowed int16→float reads |
| `packages/stt/lib/src/chunk_planner.dart` | Create | Chunk boundaries, snapped to low-RMS points |
| `packages/stt/lib/src/background_stt.dart` | Modify | Chunked transcription + progress via `SendPort` |
| `packages/stt/lib/privoice_stt.dart` | Modify | Export the two new units |
| `packages/stt/test/wav_reader_test.dart` | Create | Header/window unit tests |
| `packages/stt/test/chunk_planner_test.dart` | Create | Boundary unit tests |
| `packages/stt/test/wav_bytes.dart` | Create | Test helper that synthesizes WAV bytes |
| `packages/audio/lib/src/audio_importer.dart` | Create | `AudioImporter` interface + exception |
| `packages/audio/lib/src/audio_decoder_importer.dart` | Create | `audio_decoder` implementation |
| `packages/audio/lib/privoice_audio.dart` | Modify | Export both |
| `packages/audio/pubspec.yaml` | Modify | Add `audio_decoder` |
| `apps/mobile/lib/screens/import_screen.dart` | Create | Convert → transcribe → insert `Meeting` |
| `apps/mobile/lib/screens/home_screen.dart` | Modify | Import affordance |
| `apps/mobile/pubspec.yaml` | Modify | Add `file_picker` |
| `apps/mobile/test/fakes/fake_audio_importer.dart` | Create | Writes a canned WAV; keeps tests off native code |
| `apps/mobile/test/screens/import_screen_test.dart` | Create | Progress + error + success states |
| `STATUS.md` | Modify | Record the slice |

---

### Task 1: `WavReader`

**Files:**
- Create: `packages/stt/lib/src/wav_reader.dart`
- Create: `packages/stt/test/wav_bytes.dart`
- Create: `packages/stt/test/wav_reader_test.dart`
- Modify: `packages/stt/lib/privoice_stt.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class WavFormatException implements Exception` with `final String message`; `class WavReader` with `static Future<WavReader> open(String path)`, `int get sampleRate`, `int get sampleCount`, `Duration get duration`, `Future<Float32List> readWindow(int startSample, int count)`, `Future<void> close()`, and `static const int requiredSampleRate = 16000`.

**Why this exists:** `sherpa.readWave` loads a whole file into a `Float32List` — ~230 MB per hour of 16 kHz mono audio. This class is what makes any file length survivable.

- [ ] **Step 1: Write the test helper**

Create `packages/stt/test/wav_bytes.dart`:

```dart
import 'dart:typed_data';

/// Builds WAV bytes for tests. Defaults are the format our pipeline produces
/// (16 kHz mono 16-bit PCM); the named params exist so tests can build the
/// invalid variants the reader must reject.
Uint8List wavBytes({
  required List<int> samples, // int16 values
  int sampleRate = 16000,
  int channels = 1,
  int bitsPerSample = 16,
  int audioFormat = 1, // 1 = PCM
  /// Insert a LIST chunk before `data`. Real files do this, and a reader that
  /// assumes data lives at a fixed offset silently reads garbage.
  bool includeListChunk = false,
  /// Declare a `data` size larger than the bytes actually present.
  int? overrideDataSize,
  /// Truncate the output to this many bytes.
  int? truncateTo,
}) {
  final dataBytes = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    dataBytes.setInt16(i * 2, samples[i], Endian.little);
  }
  final data = dataBytes.buffer.asUint8List();

  final out = BytesBuilder();
  void ascii(String s) => out.add(s.codeUnits);
  void u32(int v) {
    final b = ByteData(4)..setUint32(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }
  void u16(int v) {
    final b = ByteData(2)..setUint16(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  final listChunk = includeListChunk ? 12 : 0; // 8 header + 4 payload
  ascii('RIFF');
  u32(4 + 24 + listChunk + 8 + data.length); // 'WAVE' + fmt + list + data hdr
  ascii('WAVE');

  ascii('fmt ');
  u32(16);
  u16(audioFormat);
  u16(channels);
  u32(sampleRate);
  u32(sampleRate * channels * bitsPerSample ~/ 8); // byte rate
  u16(channels * bitsPerSample ~/ 8); // block align
  u16(bitsPerSample);

  if (includeListChunk) {
    ascii('LIST');
    u32(4);
    ascii('INFO');
  }

  ascii('data');
  u32(overrideDataSize ?? data.length);
  out.add(data);

  final bytes = out.toBytes();
  return truncateTo == null ? bytes : Uint8List.sublistView(bytes, 0, truncateTo);
}
```

- [ ] **Step 2: Write the failing test**

Create `packages/stt/test/wav_reader_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_stt/privoice_stt.dart';

import 'wav_bytes.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('wav_reader'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<String> write(List<int> bytes, {String name = 'a.wav'}) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes(bytes);
    return f.path;
  }

  test('reads a valid 16 kHz mono 16-bit header', () async {
    final path = await write(wavBytes(samples: List.filled(16000, 0)));
    final r = await WavReader.open(path);
    expect(r.sampleRate, 16000);
    expect(r.sampleCount, 16000);
    expect(r.duration, const Duration(seconds: 1));
    await r.close();
  });

  test('skips a LIST chunk before data', () async {
    // A fixed-offset reader would take the LIST payload as samples.
    final path = await write(
        wavBytes(samples: [1, 2, 3, 4], includeListChunk: true));
    final r = await WavReader.open(path);
    expect(r.sampleCount, 4);
    final w = await r.readWindow(0, 4);
    expect(w[0], closeTo(1 / 32768, 1e-9));
    await r.close();
  });

  test('rejects stereo, wrong bit depth, wrong rate, non-PCM', () async {
    Future<void> expectRejected(List<int> bytes, String name) async {
      final path = await write(bytes, name: name);
      await expectLater(
          WavReader.open(path), throwsA(isA<WavFormatException>()));
    }

    await expectRejected(
        wavBytes(samples: [0, 0], channels: 2), 'stereo.wav');
    await expectRejected(
        wavBytes(samples: [0, 0], bitsPerSample: 8), 'depth8.wav');
    await expectRejected(
        wavBytes(samples: [0, 0], sampleRate: 44100), 'rate44.wav');
    await expectRejected(
        wavBytes(samples: [0, 0], audioFormat: 3), 'float.wav');
  });

  test('rejects a truncated header and an oversized data size', () async {
    final short = await write(wavBytes(samples: [0]).sublist(0, 20), name: 't.wav');
    await expectLater(WavReader.open(short), throwsA(isA<WavFormatException>()));

    final lying =
        await write(wavBytes(samples: [0, 0], overrideDataSize: 999999), name: 'l.wav');
    await expectLater(WavReader.open(lying), throwsA(isA<WavFormatException>()));
  });

  test('rejects a file that is not RIFF/WAVE', () async {
    final path = await write(List.filled(64, 0x41), name: 'junk.wav');
    await expectLater(WavReader.open(path), throwsA(isA<WavFormatException>()));
  });

  test('readWindow reads at start, middle and the exact final sample',
      () async {
    final path = await write(wavBytes(samples: [10, 20, 30, 40, 50]));
    final r = await WavReader.open(path);

    final head = await r.readWindow(0, 2);
    expect(head.length, 2);
    expect(head[0], closeTo(10 / 32768, 1e-9));

    final mid = await r.readWindow(2, 2);
    expect(mid[0], closeTo(30 / 32768, 1e-9));

    final tail = await r.readWindow(4, 1);
    expect(tail.length, 1);
    expect(tail[0], closeTo(50 / 32768, 1e-9));
    await r.close();
  });

  test('converts int16 extremes correctly', () async {
    final path = await write(wavBytes(samples: [0, 32767, -32768]));
    final r = await WavReader.open(path);
    final w = await r.readWindow(0, 3);
    expect(w[0], 0.0);
    expect(w[1], closeTo(32767 / 32768, 1e-6));
    expect(w[2], closeTo(-1.0, 1e-9));
    await r.close();
  });

  test('a window past the end throws instead of returning garbage', () async {
    final path = await write(wavBytes(samples: [1, 2, 3]));
    final r = await WavReader.open(path);
    await expectLater(r.readWindow(2, 5), throwsA(isA<RangeError>()));
    await expectLater(r.readWindow(-1, 1), throwsA(isA<RangeError>()));
    await r.close();
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/stt && flutter test test/wav_reader_test.dart`
Expected: FAIL — `WavReader` and `WavFormatException` are undefined.

- [ ] **Step 4: Write the implementation**

Create `packages/stt/lib/src/wav_reader.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

/// The WAV file could not be parsed, or is not the format the STT pipeline
/// requires (16 kHz mono 16-bit PCM).
class WavFormatException implements Exception {
  const WavFormatException(this.message);
  final String message;
  @override
  String toString() => 'WavFormatException: $message';
}

/// Reads 16 kHz mono 16-bit PCM WAV in bounded windows.
///
/// Exists because `sherpa.readWave` materialises an entire file as a
/// `Float32List` — roughly 230 MB per hour of audio at this format, on top of
/// ~1.4 GB of loaded models. Nothing here ever holds more than one window.
class WavReader {
  WavReader._(this._file, this._dataOffset, this.sampleRate, this.sampleCount);

  final RandomAccessFile _file;
  final int _dataOffset;

  final int sampleRate;
  final int sampleCount;

  static const int requiredSampleRate = 16000;
  static const int requiredChannels = 1;
  static const int requiredBitsPerSample = 16;
  static const int _bytesPerSample = 2;

  Duration get duration =>
      Duration(milliseconds: (sampleCount * 1000 / sampleRate).round());

  /// Parses and validates the header. Throws [WavFormatException] on anything
  /// this pipeline cannot consume.
  static Future<WavReader> open(String path) async {
    final file = await File(path).open();
    try {
      final length = await file.length();
      if (length < 44) {
        throw const WavFormatException('File is too short to be a WAV.');
      }

      final riff = await file.read(12);
      if (String.fromCharCodes(riff.sublist(0, 4)) != 'RIFF' ||
          String.fromCharCodes(riff.sublist(8, 12)) != 'WAVE') {
        throw const WavFormatException('Not a RIFF/WAVE file.');
      }

      int? rate, channels, bits, format;
      int? dataOffset, dataSize;
      var pos = 12;

      // Walk the chunk list. `data` is NOT at a fixed offset — real files
      // carry LIST/fact chunks first.
      while (pos + 8 <= length) {
        await file.setPosition(pos);
        final header = await file.read(8);
        if (header.length < 8) break;
        final id = String.fromCharCodes(header.sublist(0, 4));
        final size = ByteData.sublistView(header, 4, 8)
            .getUint32(0, Endian.little);
        final body = pos + 8;

        if (id == 'fmt ') {
          await file.setPosition(body);
          final fmt = await file.read(16);
          if (fmt.length < 16) {
            throw const WavFormatException('Truncated fmt chunk.');
          }
          final d = ByteData.sublistView(fmt);
          format = d.getUint16(0, Endian.little);
          channels = d.getUint16(2, Endian.little);
          rate = d.getUint32(4, Endian.little);
          bits = d.getUint16(14, Endian.little);
        } else if (id == 'data') {
          dataOffset = body;
          dataSize = size;
          break; // samples start here; no need to walk further
        }

        pos = body + size + (size.isOdd ? 1 : 0); // chunks are word-aligned
      }

      if (rate == null || channels == null || bits == null || format == null) {
        throw const WavFormatException('Missing fmt chunk.');
      }
      if (dataOffset == null || dataSize == null) {
        throw const WavFormatException('Missing data chunk.');
      }
      if (format != 1) {
        throw WavFormatException('Not PCM (format $format).');
      }
      if (channels != requiredChannels) {
        throw WavFormatException('Expected mono, got $channels channels.');
      }
      if (bits != requiredBitsPerSample) {
        throw WavFormatException('Expected 16-bit, got $bits-bit.');
      }
      if (rate != requiredSampleRate) {
        throw WavFormatException('Expected ${requiredSampleRate}Hz, got ${rate}Hz.');
      }
      if (dataOffset + dataSize > length) {
        throw const WavFormatException('data chunk extends past end of file.');
      }

      return WavReader._(file, dataOffset, rate, dataSize ~/ _bytesPerSample);
    } catch (_) {
      await file.close();
      rethrow;
    }
  }

  /// Reads [count] samples from [startSample], as float in [-1.0, 1.0].
  Future<Float32List> readWindow(int startSample, int count) async {
    if (startSample < 0 || count < 0) {
      throw RangeError('Negative window ($startSample, $count).');
    }
    if (startSample + count > sampleCount) {
      throw RangeError(
          'Window ($startSample, $count) exceeds $sampleCount samples.');
    }
    await _file.setPosition(_dataOffset + startSample * _bytesPerSample);
    final raw = await _file.read(count * _bytesPerSample);
    final view = ByteData.sublistView(raw);
    final out = Float32List(count);
    for (var i = 0; i < count; i++) {
      out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  Future<void> close() => _file.close();
}
```

Add to `packages/stt/lib/privoice_stt.dart`:

```dart
export 'src/wav_reader.dart';
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/stt && flutter test test/wav_reader_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 6: Prove the LIST-chunk test is load-bearing**

Temporarily replace the chunk walk with a fixed `dataOffset = 44`, run the tests, and confirm `skips a LIST chunk before data` FAILS. Restore the walk and confirm it passes. Report the failure output. This is the bug the test exists to catch, so it must genuinely catch it.

- [ ] **Step 7: Run the gate and commit**

Run: `melos run analyze && melos run test`
Expected: clean; all green.

```bash
git add packages/stt/lib/src/wav_reader.dart packages/stt/lib/privoice_stt.dart packages/stt/test/wav_reader_test.dart packages/stt/test/wav_bytes.dart
git commit -m "feat(stt): WavReader — bounded windowed reads of 16 kHz mono WAV"
```

---

### Task 2: `ChunkPlanner`

**Files:**
- Create: `packages/stt/lib/src/chunk_planner.dart`
- Create: `packages/stt/test/chunk_planner_test.dart`
- Modify: `packages/stt/lib/privoice_stt.dart`

**Interfaces:**
- Consumes: nothing (deliberately does no file I/O — the caller supplies RMS).
- Produces: `class Chunk` with `final int startSample`, `final int sampleCount`, `int get endSample`; `class ChunkPlanner` with `static const int targetChunkSeconds = 300`, `static const int snapWindowSeconds = 10`, `static const int rmsFrameMs = 20`, and `static Future<List<Chunk>> plan({required int sampleCount, required int sampleRate, required Future<double> Function(int startSample, int frameSamples) rmsAt})`.

**Design note:** `rmsAt` is injected rather than the planner opening the file, so this stays a pure function and tests can feed synthetic signals with no fixtures.

- [ ] **Step 1: Write the failing test**

Create `packages/stt/test/chunk_planner_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_stt/privoice_stt.dart';

const sr = 16000;
const target = ChunkPlanner.targetChunkSeconds * sr;

/// RMS that is loud everywhere — no natural cut point.
Future<double> uniform(int start, int frame) async => 0.5;

void main() {
  group('ChunkPlanner.plan', () {
    test('a file shorter than one target chunk is a single chunk', () async {
      final chunks = await ChunkPlanner.plan(
          sampleCount: 30 * sr, sampleRate: sr, rmsAt: uniform);
      expect(chunks, hasLength(1));
      expect(chunks.single.startSample, 0);
      expect(chunks.single.sampleCount, 30 * sr);
    });

    test('exactly one target chunk stays a single chunk', () async {
      final chunks = await ChunkPlanner.plan(
          sampleCount: target, sampleRate: sr, rmsAt: uniform);
      expect(chunks, hasLength(1));
    });

    test('empty audio yields no chunks', () async {
      expect(
          await ChunkPlanner.plan(
              sampleCount: 0, sampleRate: sr, rmsAt: uniform),
          isEmpty);
    });

    test('chunks partition the audio exactly', () async {
      final total = (target * 3.4).round();
      final chunks = await ChunkPlanner.plan(
          sampleCount: total, sampleRate: sr, rmsAt: uniform);

      expect(chunks.first.startSample, 0);
      expect(chunks.last.endSample, total);
      var covered = 0;
      for (var i = 0; i < chunks.length; i++) {
        expect(chunks[i].sampleCount, greaterThan(0));
        if (i > 0) {
          // contiguous, no gap and no overlap
          expect(chunks[i].startSample, chunks[i - 1].endSample);
        }
        covered += chunks[i].sampleCount;
      }
      expect(covered, total);
    });

    test('an exact multiple produces no zero-length final chunk', () async {
      final chunks = await ChunkPlanner.plan(
          sampleCount: target * 2, sampleRate: sr, rmsAt: uniform);
      expect(chunks, hasLength(2));
      for (final c in chunks) {
        expect(c.sampleCount, greaterThan(0));
      }
    });

    test('cuts inside a silent gap rather than at the raw target', () async {
      // Silence from target+2s to target+4s. The planner should move the
      // boundary into it instead of cutting at exactly `target`.
      const gapStart = target + 2 * sr;
      const gapEnd = target + 4 * sr;
      Future<double> loudWithGap(int start, int frame) async =>
          (start >= gapStart && start < gapEnd) ? 0.0 : 0.8;

      final chunks = await ChunkPlanner.plan(
          sampleCount: target * 2, sampleRate: sr, rmsAt: loudWithGap);

      expect(chunks.length, greaterThanOrEqualTo(2));
      final boundary = chunks[0].endSample;
      expect(boundary, greaterThanOrEqualTo(gapStart));
      expect(boundary, lessThan(gapEnd));
    });

    test('with no silence, the boundary stays at the target', () async {
      final chunks = await ChunkPlanner.plan(
          sampleCount: target * 2, sampleRate: sr, rmsAt: uniform);
      // Uniform RMS: the first candidate wins, which is the earliest offset in
      // the search window, so the boundary must land within the snap window.
      final boundary = chunks[0].endSample;
      expect((boundary - target).abs(),
          lessThanOrEqualTo(ChunkPlanner.snapWindowSeconds * sr));
    });

    test('boundaries never fall outside the audio', () async {
      final total = target + 3 * sr; // second chunk shorter than the window
      final chunks = await ChunkPlanner.plan(
          sampleCount: total, sampleRate: sr, rmsAt: uniform);
      for (final c in chunks) {
        expect(c.startSample, greaterThanOrEqualTo(0));
        expect(c.endSample, lessThanOrEqualTo(total));
      }
      expect(chunks.last.endSample, total);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/stt && flutter test test/chunk_planner_test.dart`
Expected: FAIL — `ChunkPlanner` and `Chunk` are undefined.

- [ ] **Step 3: Write the implementation**

Create `packages/stt/lib/src/chunk_planner.dart`:

```dart
import 'dart:math' as math;

/// One contiguous span of samples to transcribe.
class Chunk {
  const Chunk({required this.startSample, required this.sampleCount});

  final int startSample;
  final int sampleCount;

  int get endSample => startSample + sampleCount;
}

/// Splits long audio into transcribable spans, cutting where the audio is
/// quietest so a word is less likely to be severed mid-utterance.
///
/// Chunks partition the audio exactly — contiguous and non-overlapping — so
/// the transcript needs no de-duplication when the pieces are joined.
class ChunkPlanner {
  /// Roughly how long each chunk should be.
  static const int targetChunkSeconds = 300;

  /// How far either side of a target boundary to look for a quiet point.
  static const int snapWindowSeconds = 10;

  /// Granularity of the RMS scan.
  static const int rmsFrameMs = 20;

  static Future<List<Chunk>> plan({
    required int sampleCount,
    required int sampleRate,
    required Future<double> Function(int startSample, int frameSamples) rmsAt,
  }) async {
    if (sampleCount <= 0) return const <Chunk>[];

    final target = targetChunkSeconds * sampleRate;
    if (sampleCount <= target) {
      return [Chunk(startSample: 0, sampleCount: sampleCount)];
    }

    final frame = math.max(1, (rmsFrameMs * sampleRate / 1000).round());
    final snap = snapWindowSeconds * sampleRate;

    final bounds = <int>[0];
    var next = target;
    while (next < sampleCount) {
      final lo = math.max(bounds.last + frame, next - snap);
      final hi = math.min(sampleCount - frame, next + snap);

      var best = math.min(next, sampleCount - 1);
      var bestRms = double.infinity;
      for (var s = lo; s <= hi; s += frame) {
        final rms = await rmsAt(s, frame);
        if (rms < bestRms) {
          bestRms = rms;
          best = s;
        }
      }

      // Never move backwards; that would produce an empty or negative chunk.
      if (best <= bounds.last) best = math.min(next, sampleCount - 1);

      bounds.add(best);
      next = best + target;
    }
    bounds.add(sampleCount);

    final chunks = <Chunk>[];
    for (var i = 0; i < bounds.length - 1; i++) {
      final len = bounds[i + 1] - bounds[i];
      if (len > 0) {
        chunks.add(Chunk(startSample: bounds[i], sampleCount: len));
      }
    }
    return chunks;
  }
}
```

Add to `packages/stt/lib/privoice_stt.dart`:

```dart
export 'src/chunk_planner.dart';
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/stt && flutter test test/chunk_planner_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 5: Prove the silence test is load-bearing**

Temporarily make the planner ignore RMS (always cut at exactly `next`), run the tests, and confirm `cuts inside a silent gap rather than at the raw target` FAILS. Restore and confirm it passes. Report the failure output.

- [ ] **Step 6: Run the gate and commit**

Run: `melos run analyze && melos run test`
Expected: clean; all green.

```bash
git add packages/stt/lib/src/chunk_planner.dart packages/stt/lib/privoice_stt.dart packages/stt/test/chunk_planner_test.dart
git commit -m "feat(stt): ChunkPlanner — cut long audio at the quietest nearby point"
```

---

### Task 3: Chunked transcription with progress

**Files:**
- Modify: `packages/stt/lib/src/background_stt.dart` (whole file — the request type gains a field and `_transcribeSync` becomes async and chunked)
- Test: `packages/stt/test/chunked_transcribe_test.dart` (create)

**Interfaces:**
- Consumes: `WavReader` (Task 1) and `ChunkPlanner`/`Chunk` (Task 2).
- Produces: `transcribeFileInBackground(SttModelPaths paths, String wavPath, {void Function(double fraction)? onProgress})`; `SttRequest` gains `final SendPort? progressPort`.

**Two things to know before starting.**

1. **`compute()` cannot report progress on its own** — it returns a single value. But a `SendPort` *is* sendable, so the fix is to put one in `SttRequest`, have the isolate `send` fractions, and let the caller listen on a `ReceivePort`. `compute` is kept; do not hand-roll `Isolate.spawn`.
2. **`compute` accepts an async callback**, so `_transcribeSync` becomes `Future<Transcript> _transcribeAsync` — required because `WavReader` is async.

**This is the risky task:** it rewrites the transcription path that recording already depends on and that has been verified on two devices. A short file must produce exactly one chunk, so recording behaviour is preserved by construction. The existing record-flow tests are the guard and must not be edited.

- [ ] **Step 1: Write the failing test**

Create `packages/stt/test/chunked_transcribe_test.dart`. This tests the pure chunk-assembly logic without sherpa, by exercising the same planner + reader the isolate uses:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_stt/privoice_stt.dart';

import 'wav_bytes.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('chunked'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a short file plans exactly one chunk covering all samples', () async {
    // This is what preserves the existing recording behaviour: one chunk in,
    // one decode pass, same result as the old whole-file path.
    final f = File('${tmp.path}/short.wav');
    await f.writeAsBytes(wavBytes(samples: List.filled(16000 * 30, 0)));
    final r = await WavReader.open(f.path);

    final chunks = await ChunkPlanner.plan(
      sampleCount: r.sampleCount,
      sampleRate: r.sampleRate,
      rmsAt: (s, n) async => rmsOf(await r.readWindow(s, n)),
    );

    expect(chunks, hasLength(1));
    expect(chunks.single.sampleCount, r.sampleCount);
    await r.close();
  });

  test('rmsOf is 0 for silence and positive for signal', () async {
    expect(rmsOf(Float32List.fromList([0, 0, 0])), 0.0);
    expect(rmsOf(Float32List.fromList([0.5, -0.5])), closeTo(0.5, 1e-6));
    expect(rmsOf(Float32List(0)), 0.0);
  });

  test('segments assembled from chunks join in order with real times', () {
    // Transcript.fromSegments is what turns per-chunk text into fullText, so
    // pin the ordering and the timing arithmetic here.
    const sr = 16000;
    final t = Transcript.fromSegments([
      TranscriptSegment(text: 'hello there', startSec: 0, endSec: 5),
      TranscriptSegment(text: 'second part', startSec: 5, endSec: 9),
    ], const Duration(seconds: 9));

    expect(t.fullText, 'hello there second part');
    expect(t.segments, hasLength(2));
    expect(t.segments[1].startSec, 5);
    expect(sr, 16000); // guards against an accidental rate change in this test
  });
}
```

`rmsOf` comes from `background_stt.dart`, which `privoice_stt.dart` already
exports, so the existing package import covers it once Step 3 defines it.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/stt && flutter test test/chunked_transcribe_test.dart`
Expected: FAIL — `rmsOf` is undefined.

- [ ] **Step 3: Rewrite `background_stt.dart`**

Replace the file's contents below the imports. Keep `SttRequest.from` working for existing callers by giving the new field a default.

```dart
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'chunk_planner.dart';
import 'stt_engine.dart';
import 'transcript.dart';
import 'wav_reader.dart';

/// Root-mean-square amplitude of [samples], or 0 for an empty window.
///
/// Public because [ChunkPlanner] takes RMS as an injected callback and both the
/// isolate and its tests need the same definition.
double rmsOf(Float32List samples) {
  if (samples.isEmpty) return 0.0;
  var sum = 0.0;
  for (final s in samples) {
    sum += s * s;
  }
  return math.sqrt(sum / samples.length);
}

/// Sendable request for a one-shot background transcription.
class SttRequest {
  const SttRequest({
    required this.encoder,
    required this.decoder,
    required this.joiner,
    required this.tokens,
    required this.wavPath,
    this.progressPort,
  });

  factory SttRequest.from(
    SttModelPaths paths,
    String wavPath, {
    SendPort? progressPort,
  }) =>
      SttRequest(
        encoder: paths.encoder,
        decoder: paths.decoder,
        joiner: paths.joiner,
        tokens: paths.tokens,
        wavPath: wavPath,
        progressPort: progressPort,
      );

  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;
  final String wavPath;

  /// Where the isolate reports completed-fraction updates. A `SendPort` is
  /// sendable, which is what lets `compute` — normally a single-value call —
  /// stream progress back.
  final SendPort? progressPort;
}

/// Runs init → chunked transcribe → dispose inside a one-shot isolate (via
/// [compute]) so the model load and inference never block the UI.
///
/// The audio is transcribed in spans planned by [ChunkPlanner] and read in
/// windows by [WavReader], so peak memory is bounded by one chunk rather than
/// the whole file. A file shorter than one chunk is transcribed in a single
/// pass, which is exactly what the previous whole-file implementation did.
Future<Transcript> transcribeFileInBackground(
  SttModelPaths paths,
  String wavPath, {
  void Function(double fraction)? onProgress,
}) async {
  if (onProgress == null) {
    return compute(_transcribeAsync, SttRequest.from(paths, wavPath));
  }
  final port = ReceivePort();
  port.listen((message) {
    if (message is double) onProgress(message);
  });
  try {
    return await compute(
      _transcribeAsync,
      SttRequest.from(paths, wavPath, progressPort: port.sendPort),
    );
  } finally {
    port.close();
  }
}

/// Top-level so it can run in the [compute] isolate.
Future<Transcript> _transcribeAsync(SttRequest req) async {
  sherpa.initBindings();

  final model = sherpa.OfflineModelConfig(
    transducer: sherpa.OfflineTransducerModelConfig(
      encoder: req.encoder,
      decoder: req.decoder,
      joiner: req.joiner,
    ),
    tokens: req.tokens,
    modelType: 'nemo_transducer',
    numThreads: 2,
    debug: false,
  );
  final rec = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(model: model),
  );

  WavReader? reader;
  try {
    reader = await WavReader.open(req.wavPath);
    final r = reader;

    final chunks = await ChunkPlanner.plan(
      sampleCount: r.sampleCount,
      sampleRate: r.sampleRate,
      rmsAt: (start, frame) async => rmsOf(await r.readWindow(start, frame)),
    );

    final segments = <TranscriptSegment>[];
    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final samples = await r.readWindow(chunk.startSample, chunk.sampleCount);

      final stream = rec.createStream();
      stream.acceptWaveform(samples: samples, sampleRate: r.sampleRate);
      rec.decode(stream);
      final text = rec.getResult(stream).text;
      stream.free();

      segments.add(TranscriptSegment(
        text: text,
        startSec: chunk.startSample / r.sampleRate,
        endSec: chunk.endSample / r.sampleRate,
      ));

      req.progressPort?.send((i + 1) / chunks.length);
    }

    return Transcript.fromSegments(segments, r.duration);
  } finally {
    rec.free();
    await reader?.close();
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/stt && flutter test`
Expected: PASS, including the new file.

- [ ] **Step 5: Confirm the recording path is untouched**

Run: `cd apps/mobile && flutter test test/screens/record_screen_test.dart test/privacy_gate_test.dart`
Expected: PASS with **no edits to either test file**. Run `git status` and confirm no file under `apps/mobile/test/` is modified. If a record-flow test needed changing, the unification was not behaviour-preserving — fix the implementation, not the test.

- [ ] **Step 6: Run the gate and commit**

Run: `melos run analyze && melos run test`
Expected: clean; all green.

```bash
git add packages/stt
git commit -m "feat(stt): chunked transcription with progress, one path for record and import"
```

---

### Task 4: `AudioImporter`

**Files:**
- Create: `packages/audio/lib/src/audio_importer.dart`
- Create: `packages/audio/lib/src/audio_decoder_importer.dart`
- Modify: `packages/audio/lib/privoice_audio.dart`
- Modify: `packages/audio/pubspec.yaml`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `class AudioImportException implements Exception` with `final String message`; `abstract class AudioImporter` with `Future<void> toSttWav({required String sourcePath, required String targetPath})`; `class AudioDecoderImporter implements AudioImporter`.

**Why an interface:** the project rule is that native-binding code sits behind a swappable Dart interface, and `audio_decoder` is young (0.8.1, ~6k downloads). It is MIT and thin, so if it stalls we vendor or fork it — as we already do for `fllama` — and the interface keeps that swap to one file.

- [ ] **Step 1: Add the dependency**

```bash
cd packages/audio && flutter pub add audio_decoder
```

Then verify nothing else moved:

```bash
cd ../.. && git diff pubspec.lock | grep -E "^\+|^-" | grep -v audio_decoder
```

Expected: only lines relating to `audio_decoder` (and its own transitive additions). **If any existing package's version changed, stop and report it** — adding `flutter_launcher_icons` to this workspace previously forced a workspace-wide `xml` downgrade, which is why this check exists.

- [ ] **Step 2: Write the interface**

Create `packages/audio/lib/src/audio_importer.dart`:

```dart
/// The source file could not be decoded — unsupported container, DRM, no
/// audio track, or corrupt data. [message] is user-facing.
class AudioImportException implements Exception {
  const AudioImportException(this.message);
  final String message;
  @override
  String toString() => 'AudioImportException: $message';
}

/// Converts an arbitrary audio or video file into the one format the on-device
/// STT pipeline accepts.
///
/// Behind an interface so the native decoder can be replaced without touching
/// callers, per the project rule that native bindings stay swappable.
abstract class AudioImporter {
  /// Decode [sourcePath] — any container the platform supports, including
  /// video, from which the audio track is extracted — and write 16 kHz mono
  /// 16-bit PCM WAV to [targetPath].
  ///
  /// Throws [AudioImportException] if the source cannot be decoded.
  Future<void> toSttWav({
    required String sourcePath,
    required String targetPath,
  });
}
```

- [ ] **Step 3: Write the implementation**

Create `packages/audio/lib/src/audio_decoder_importer.dart`:

```dart
import 'dart:io';

import 'package:audio_decoder/audio_decoder.dart';

import 'audio_importer.dart';

/// [AudioImporter] backed by `audio_decoder`, which wraps the platform
/// decoders (AVFoundation on iOS, MediaCodec on Android) rather than bundling
/// FFmpeg — FFmpegKit was archived in June 2025.
class AudioDecoderImporter implements AudioImporter {
  const AudioDecoderImporter();

  /// The format `WavReader` and the STT models require. Kept here as the
  /// single place the conversion target is stated.
  static const int sampleRate = 16000;
  static const int channels = 1;
  static const int bitDepth = 16;

  @override
  Future<void> toSttWav({
    required String sourcePath,
    required String targetPath,
  }) async {
    if (!await File(sourcePath).exists()) {
      throw const AudioImportException('That file could no longer be found.');
    }
    try {
      await AudioDecoder.convertToWav(
        sourcePath,
        targetPath,
        sampleRate: sampleRate,
        channels: channels,
        bitDepth: bitDepth,
      );
    } catch (e) {
      // Delete a partial file so a retry starts clean and no half-WAV is left
      // behind for the reader to choke on.
      final partial = File(targetPath);
      if (await partial.exists()) {
        await partial.delete();
      }
      throw AudioImportException(
        "That file couldn't be read. It may be an unsupported format, "
        'protected, or damaged.',
      );
    }
    final out = File(targetPath);
    if (!await out.exists() || await out.length() == 0) {
      throw const AudioImportException(
        'That file has no audio track we can read.',
      );
    }
  }
}
```

Add to `packages/audio/lib/privoice_audio.dart`:

```dart
export 'src/audio_importer.dart';
export 'src/audio_decoder_importer.dart';
```

- [ ] **Step 4: Verify it analyzes and the suite is green**

Run: `melos run analyze && melos run test`
Expected: clean; all green.

There is deliberately **no unit test for `AudioDecoderImporter`** — every branch worth asserting is either a call into native platform decoders or trivial file existence, and a test that mocks `AudioDecoder.convertToWav` would assert only that we call the function we obviously call. App-level behaviour is covered through `FakeAudioImporter` in Task 5. Say so in your report rather than writing a vacuous test.

- [ ] **Step 5: Commit**

```bash
git add packages/audio pubspec.lock
git commit -m "feat(audio): AudioImporter — transcode any container to STT WAV"
```

---

### Task 5: Import flow

**Files:**
- Create: `apps/mobile/lib/screens/import_screen.dart`
- Create: `apps/mobile/test/fakes/fake_audio_importer.dart`
- Create: `apps/mobile/test/screens/import_screen_test.dart`
- Modify: `apps/mobile/lib/screens/home_screen.dart` (add the affordance; `_RecordDock` is at :413)
- Modify: `apps/mobile/pubspec.yaml`

**Interfaces:**
- Consumes: `AudioImporter`/`AudioImportException` (Task 4), `transcribeFileInBackground(..., onProgress:)` (Task 3), `WavReader` (Task 1).
- Produces: `class ImportScreen extends StatefulWidget` with `const ImportScreen({super.key, required this.repository, required this.sourcePath, this.importer})`, popping `true` when a `Meeting` was saved.

**Exact copy** (asserted by tests; do not paraphrase):
- Home affordance label: `Import`
- App bar title: `Import recording`
- Converting phase: `Converting audio…`
- Transcribing phase: `Transcribing… 40%` — i.e. `Transcribing… $percent%`
- Error heading: `Couldn't import that file`
- Retry button: `Try again`

**Design note:** `ImportScreen` takes `sourcePath`, not a picker. Home does the picking. That keeps the screen testable without plugging in `file_picker`, which cannot run in a widget test.

- [ ] **Step 1: Add the dependency**

```bash
cd apps/mobile && flutter pub add file_picker
```

Then confirm nothing else moved:

```bash
cd ../.. && git diff pubspec.lock | grep -E "^\+|^-" | grep -v file_picker
```

Expected: only `file_picker` and its transitive additions. Stop and report if an existing package's version changed.

- [ ] **Step 2: Write the fake**

Create `apps/mobile/test/fakes/fake_audio_importer.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:privoice_audio/privoice_audio.dart';

/// Writes a real, valid 16 kHz mono 16-bit WAV so the import flow can be
/// tested end to end without invoking native decoders.
class FakeAudioImporter implements AudioImporter {
  FakeAudioImporter({this.seconds = 2, this.failWith});

  final int seconds;

  /// When set, [toSttWav] throws this instead of writing a file.
  final AudioImportException? failWith;

  int calls = 0;

  @override
  Future<void> toSttWav({
    required String sourcePath,
    required String targetPath,
  }) async {
    calls++;
    final fail = failWith;
    if (fail != null) throw fail;

    const sampleRate = 16000;
    final samples = sampleRate * seconds;
    final data = ByteData(samples * 2); // all zeros: silence is fine here
    final out = BytesBuilder();
    void ascii(String s) => out.add(s.codeUnits);
    void u32(int v) =>
        out.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
    void u16(int v) =>
        out.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());

    ascii('RIFF');
    u32(36 + data.lengthInBytes);
    ascii('WAVE');
    ascii('fmt ');
    u32(16);
    u16(1);
    u16(1);
    u32(sampleRate);
    u32(sampleRate * 2);
    u16(2);
    u16(16);
    ascii('data');
    u32(data.lengthInBytes);
    out.add(data.buffer.asUint8List());

    await File(targetPath).writeAsBytes(out.toBytes());
  }
}
```

- [ ] **Step 3: Write the failing test**

Create `apps/mobile/test/screens/import_screen_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/import_screen.dart';
import 'package:privoice_audio/privoice_audio.dart';
import 'package:privoice_core/privoice_core.dart';

import '../fakes/fake_audio_importer.dart';
import '../fakes/fake_meeting_repository.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('import_screen'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<String> aSource() async {
    final f = File('${tmp.path}/source.m4a');
    await f.writeAsBytes([0, 1, 2, 3]);
    return f.path;
  }

  Future<void> pump(
    WidgetTester tester, {
    required MeetingRepository repo,
    required String sourcePath,
    AudioImporter? importer,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: ImportScreen(
        repository: repo,
        sourcePath: sourcePath,
        importer: importer ?? FakeAudioImporter(),
      ),
    ));
    await tester.pump();
  }

  testWidgets('shows the import title and a converting state first',
      (tester) async {
    await pump(tester, repo: FakeMeetingRepository(), sourcePath: await aSource());
    expect(find.text('Import recording'), findsOneWidget);
    expect(find.text('Converting audio…'), findsOneWidget);
  });

  testWidgets('a decode failure shows the error and saves no meeting',
      (tester) async {
    final repo = FakeMeetingRepository();
    await pump(
      tester,
      repo: repo,
      sourcePath: await aSource(),
      importer: FakeAudioImporter(
        failWith: const AudioImportException('That file has no audio track.'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Couldn't import that file"), findsOneWidget);
    expect(find.text('That file has no audio track.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(await repo.all(), isEmpty);
  });

  testWidgets('a missing model shows an error rather than crashing',
      (tester) async {
    // No STT model is installed in the test environment, so the transcribe
    // step must fail gracefully — not throw into the widget tree.
    final repo = FakeMeetingRepository();
    await pump(tester, repo: repo, sourcePath: await aSource());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text("Couldn't import that file"), findsOneWidget);
    expect(await repo.all(), isEmpty);
  });
}
```

> Note on scope: these tests cover the conversion and failure paths. They do
> **not** assert a successful end-to-end import, because that needs a real STT
> model and cannot run in a widget test — that case is covered by Task 7's
> device verification. Do not fake `transcribeFileInBackground` into passing;
> an assertion that only proves a stub was called would be worse than no test.

- [ ] **Step 4: Run the tests to verify they fail**

Run: `cd apps/mobile && flutter test test/screens/import_screen_test.dart`
Expected: FAIL — `import_screen.dart` does not exist.

- [ ] **Step 5: Write `ImportScreen`**

Create `apps/mobile/lib/screens/import_screen.dart`. Follow the structure of
`record_screen.dart` (phase enum, `_error` string, error view with a retry
control) so the two read the same way.

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:privoice_audio/privoice_audio.dart';
import 'package:privoice_core/privoice_core.dart';
import 'package:privoice_stt/privoice_stt.dart';

import '../model_paths.dart';

enum _Phase { converting, transcribing, error }

/// Import an existing recording: transcode → chunked transcribe → persist a
/// [Meeting]. Pops `true` when a meeting was saved.
///
/// Takes a [sourcePath] rather than doing its own file picking, so it can be
/// widget-tested without `file_picker`.
class ImportScreen extends StatefulWidget {
  const ImportScreen({
    super.key,
    required this.repository,
    required this.sourcePath,
    this.importer,
  });

  final MeetingRepository repository;
  final String sourcePath;
  final AudioImporter? importer;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  late final AudioImporter _importer =
      widget.importer ?? const AudioDecoderImporter();

  _Phase _phase = _Phase.converting;
  double _progress = 0;
  String _error = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    setState(() {
      _phase = _Phase.converting;
      _progress = 0;
      _error = '';
    });

    String? wavPath;
    try {
      final dir = await getApplicationDocumentsDirectory();
      wavPath = p.join(
        dir.path,
        'imported_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      await _importer.toSttWav(
        sourcePath: widget.sourcePath,
        targetPath: wavPath,
      );

      final model = await ModelLocator.parakeet();
      if (model == null) {
        throw const AudioImportException(
          'The speech model is not ready yet. Try again once setup finishes.',
        );
      }

      if (!mounted) return;
      setState(() => _phase = _Phase.transcribing);

      final reader = await WavReader.open(wavPath);
      final duration = reader.duration;
      await reader.close();

      final transcript = await transcribeFileInBackground(
        model,
        wavPath,
        onProgress: (f) {
          if (mounted) setState(() => _progress = f);
        },
      );

      await widget.repository.insert(Meeting(
        title: _defaultTitle(),
        createdAt: DateTime.now(),
        audioPath: wavPath,
        durationMs: duration.inMilliseconds,
        transcript: transcript.fullText,
        status: MeetingStatus.done,
      ));

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // Leave nothing half-written behind: a partial WAV would otherwise sit
      // in app storage forever, and no Meeting row is inserted on failure.
      if (wavPath != null) {
        final f = File(wavPath);
        if (await f.exists()) await f.delete();
      }
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = e is AudioImportException
            ? e.message
            : "That file couldn't be imported.";
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
    return Scaffold(
      appBar: AppBar(title: const Text('Import recording')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: switch (_phase) {
            _Phase.converting => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                      width: 120, child: LinearProgressIndicator(minHeight: 4)),
                  SizedBox(height: 16),
                  Text('Converting audio…'),
                ],
              ),
            _Phase.transcribing => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(
                        minHeight: 4, value: _progress == 0 ? null : _progress),
                  ),
                  const SizedBox(height: 16),
                  Text('Transcribing… ${(_progress * 100).round()}%'),
                ],
              ),
            _Phase.error => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: scheme.error),
                  const SizedBox(height: 16),
                  Text("Couldn't import that file",
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(_error,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _run,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Try again'),
                  ),
                ],
              ),
          },
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd apps/mobile && flutter test test/screens/import_screen_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 7: Wire the Home affordance**

In `apps/mobile/lib/screens/home_screen.dart`, add an `Import` action. Put it
in the app-bar row beside the existing settings gear rather than inside
`_RecordDock` — the dock's tap target is the record button and must not gain a
competing one. Use `IconButton(icon: Icon(Icons.file_upload_outlined), tooltip: 'Import')`.

Its handler picks a file and pushes `ImportScreen`:

```dart
Future<void> _import() async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const [
      'm4a', 'mp3', 'wav', 'aac', 'aiff', 'caf', 'flac',
      'ogg', 'opus', 'amr', 'mp4', 'mov', 'webm',
    ],
  );
  final path = picked?.files.single.path;
  if (path == null || !mounted) return; // cancelled

  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => ImportScreen(
        repository: widget.repository,
        sourcePath: path,
      ),
    ),
  );
  if (saved == true) _reload(); // same refresh the record flow triggers
}
```

Check what the record flow calls to refresh the list after `pop(true)` (around
`home_screen.dart:75`) and call exactly that, rather than inventing a second
refresh path.

- [ ] **Step 8: Add the Home test and run the gate**

Add to `apps/mobile/test/screens/home_screen_test.dart`, matching the file's
existing helpers:

```dart
  testWidgets('offers an Import action', (tester) async {
    await tester.pumpWidget(host(FakeMeetingRepository(), manager: readyManager()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Import'), findsOneWidget);
  });
```

Run: `melos run analyze && melos run test`
Expected: clean; all green.

- [ ] **Step 9: Commit**

```bash
git add apps/mobile pubspec.lock
git commit -m "feat(mobile): import an existing recording or video"
```

---

### Task 6: STATUS.md

**Files:**
- Modify: `STATUS.md`

- [ ] **Step 1: Update it**

`CLAUDE.md` treats STATUS.md as part of *done*:

- Bump **Last updated**.
- Add a Build slices row for audio import, marked **code-complete, NOT verified** — device verification is Task 7. The repo rule is that ✅ means verified on a device, so do not claim it here.
- Record under Environment facts: the conversion target (16 kHz mono 16-bit), the tuning constants (`targetChunkSeconds = 300`, `snapWindowSeconds = 10`, `rmsFrameMs = 20`), and that `audio_decoder` replaces FFmpegKit, which was archived in June 2025.
- Record under Known gaps: no OS share-sheet / "Open with" integration yet (picker only); `webm` likely will not decode on iOS; chunk boundaries degrade to a fixed cut on continuous speech with no pauses, with Silero VAD (`vad.dart`, already in `sherpa_onnx`) as the upgrade path that would also unlock silence skipping.

- [ ] **Step 2: Commit**

```bash
git add STATUS.md
git commit -m "docs(status): audio import code-complete"
```

---

### Task 7: Verify on a device

Tests passing is not the feature working. `CLAUDE.md` requires ✅ to mean verified.

- [ ] **Step 1: Build and install**

```bash
export PATH="/opt/homebrew/bin:$HOME/.pub-cache/bin:$PATH"
cd apps/mobile && flutter build ios --release
xcrun devicectl device install app --device 938C24C1-5640-5F7C-8772-28F813BD1D47 \
  build/ios/iphoneos/Runner.app
```

The device must be unlocked or the install and launch both fail. Note that
reinstalling can replace the app's data container and wipe downloaded models,
in which case onboarding will re-download them.

- [ ] **Step 2: Import a short audio file**

Put a short `.m4a` or `.mp3` on the device (AirDrop or Files) and import it.
Confirm: conversion completes, progress advances, a meeting appears with a
real transcript, and the duration shown matches the file.

- [ ] **Step 3: Import a video file**

Import a `.mp4` — ideally a real Zoom/Teams recording, since that is the case
this slice exists for. Confirm the audio track is extracted and transcribed.

- [ ] **Step 4: Import something long**

Import a file over 10 minutes. This is the chunking path. Confirm progress
advances in steps rather than jumping 0 → 100, the transcript covers the whole
recording rather than only the first chunk, and the app does not run out of
memory. **Also check for words severed at chunk boundaries** — roughly every
5 minutes of transcript — and report what you find, since that is the known
trade-off of RMS snapping.

- [ ] **Step 5: Import something unsupported**

Try a file that is not audio (rename a `.txt` to `.m4a`). Confirm the error
message appears, `Try again` is offered, and no meeting is created.

- [ ] **Step 6: Confirm recording still works**

Record a short meeting on the device. This is the regression check for
unifying the transcription path — it must behave exactly as before.

- [ ] **Step 7: Build for Android**

```bash
cd apps/mobile && flutter build apk --debug
```

Confirms `audio_decoder` and `file_picker` do not break the Android build.

- [ ] **Step 8: Flip STATUS.md to verified and commit**

Only after the steps above pass. Record the long-import observations
(chunk count, whether boundary artefacts appeared) in the STATUS entry, since
they are the empirical basis for tuning the constants later.

```bash
git add STATUS.md
git commit -m "docs(status): audio import verified on device"
```

---

## Self-Review

**Spec coverage:** `AudioImporter` + `audio_decoder` → Task 4. `WavReader` →
Task 1. `ChunkPlanner` + snapping → Task 2. Chunked transcription, progress,
and unifying the recording path → Task 3. Picker, extension list, and
`ImportScreen` with its two-phase progress → Task 5. Error-handling table →
Tasks 4 and 5 (decode failure, no audio track, partial-file cleanup, no
`Meeting` on failure, cancelled picker). `durationMs` from `WavReader` → Task
5. Storage decision (keep the converted WAV) → Task 5. STATUS → Task 6.
Device verification, including the video and long-file cases → Task 7.

**Type consistency:** `WavReader.open/readWindow/duration/sampleCount/close`
are used identically in Tasks 1, 3 and 5. `ChunkPlanner.plan`'s `rmsAt`
signature matches its call site in Task 3, and `rmsOf` is defined once in
`background_stt.dart` and exported for the Task 3 test.
`AudioImporter.toSttWav`'s named parameters match `FakeAudioImporter` and
`ImportScreen`. `AudioImportException.message` is used for user-facing copy in
both Task 4 and Task 5.

**Deliberate test omissions, stated rather than hidden:** there is no unit test
for `AudioDecoderImporter` (every meaningful branch is a native call), and the
`ImportScreen` tests do not assert a successful end-to-end import (it needs a
real STT model). Both are covered by Task 7 instead. Writing tests that only
prove a stub was invoked would be worse than the honest gap.

**Known soft spots:** Task 5 Step 7 asks the implementer to read
`home_screen.dart` for the existing list-refresh call rather than guessing at
its name, and Task 6 describes STATUS.md edits in prose because that file's
format is prose. Both require reading current file contents; inventing code
against an unread structure would be worse.
