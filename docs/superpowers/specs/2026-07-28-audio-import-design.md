# Audio import — design

**Date:** 2026-07-28
**Slice:** B (mobile, on-device) — second of the batch decomposed on 2026-07-27
**Status:** approved, ready for implementation plan

## Problem

Privoice can only transcribe audio it recorded itself. Every meeting a user
already has — a Zoom `.mp4`, a Teams recording, a voice memo, an `.m4a` from
another app — is unreachable. This is the feature the user asked for first.

Two constraints shape the whole design:

1. **STT is WAV-only.** `packages/stt` calls `sherpa.readWave(wavPath)`, and
   recording is fixed at 16 kHz mono by `RecordingConfig`. Anything imported
   must be transcoded to that exact format first.
2. **`readWave` loads the entire file into a `Float32List`.** At 16 kHz mono
   that is ~230 MB of RAM per hour of audio, on top of ~1.4 GB of loaded
   models. A two-hour import would need ~460 MB and would plausibly be killed
   on a 4 GB device (iPhone 13) even with the
   `com.apple.developer.kernel.increased-memory-limit` entitlement. Long
   recordings have this same latent risk today.

## Scope

**In:** an in-app file picker accepting audio **and** video containers, native
transcoding to 16 kHz mono 16-bit WAV, chunked transcription that bounds
memory at any input length, progress reporting, and unifying the recording
path onto the same chunked implementation.

**Out, deliberately:** OS share sheet / "Open with" registration (a good
follow-up — it needs iOS UTI declarations, an Android intent-filter, and a
cold-start import path); audio playback; VAD-based splitting; silence
skipping; diarization.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Entry point | In-app picker, audio **+** `.mp4`/`.mov` | Zoom, Teams and Meet all export video. Audio-only would miss the most common recording a user actually has. |
| Long files | Chunked transcription | Bounds memory at any length and gives real progress. A duration cap would reject exactly the 90-minute workshop that most needs importing. |
| Storage | Keep the converted WAV | Matches recordings: one format behind `audioPath`, and re-transcription stays possible when a better STT model lands. Costs ~115 MB per imported hour. |
| Chunk boundaries | Snap to lowest-RMS point near the target | No extra model, no download, no overlap-dedupe. Pure Dart, so it unit-tests properly. |
| Recording path | Unified onto the chunked implementation | One path to maintain, and it fixes the same latent OOM for long recordings. A short file is simply one chunk. |

## Feasibility check (done before this spec)

`flutter pub add --dry-run file_picker audio_decoder` resolves to
**`audio_decoder 0.8.1`** and **`file_picker 11.0.2`** with **zero
downgrades** of existing packages. This was verified explicitly because an
earlier attempt to add `flutter_launcher_icons` to this workspace resolved to
a years-old version and forced a workspace-wide downgrade of `xml`.

`audio_decoder` requires iOS 13+ / Android API 24+. Privoice is at iOS 14 and
`minSdk = 24`, so **no platform floor changes are needed**.

## Architecture

### `packages/audio` — `AudioImporter`

```dart
abstract class AudioImporter {
  /// Convert [sourcePath] — any container the platform can decode, including
  /// video — into 16 kHz mono 16-bit PCM WAV at [targetPath].
  ///
  /// Throws [AudioImportException] when the source cannot be decoded.
  Future<void> toSttWav({
    required String sourcePath,
    required String targetPath,
  });
}

class AudioImportException implements Exception {
  const AudioImportException(this.message);
  final String message; // user-facing
}
```

Implementation (`AudioDecoderImporter`) wraps:

```dart
await AudioDecoder.convertToWav(
  sourcePath, targetPath,
  sampleRate: 16000, channels: 1, bitDepth: 16,
);
```

The interface exists for two reasons: the project rule that native-binding
code stays behind a swappable Dart interface, and specifically because
`audio_decoder` is young (0.8.1, ~6k downloads, 12 likes). It is MIT and thin
— a wrapper over `AVFoundation` and `MediaCodec` — so if it stalls we vendor
or fork it, exactly as we already do for `fllama`. The interface keeps that
swap to one file.

### `packages/stt` — `WavReader` (pure Dart)

The unit that bounds memory. Nothing else ever holds a whole file.

```dart
class WavReader {
  static Future<WavReader> open(String path);   // parses + validates header

  int get sampleRate;      // must be 16000
  int get sampleCount;
  Duration get duration;

  /// Reads exactly [count] samples starting at [startSample], converting
  /// int16 → float in [-1.0, 1.0]. Backed by RandomAccessFile: only this
  /// window is ever in memory.
  Future<Float32List> readWindow(int startSample, int count);

  Future<void> close();
}
```

Header parsing walks RIFF chunks properly rather than assuming `data` is at a
fixed offset — real files carry `LIST`/`fact` chunks first. Validates 16 kHz,
mono, 16-bit PCM and throws otherwise: we control the conversion, so a stereo
or 48 kHz file arriving means the converter misbehaved, and that must surface
loudly rather than be silently mis-transcribed.

### `packages/stt` — `ChunkPlanner` (pure Dart)

```dart
class Chunk {
  final int startSample;
  final int sampleCount;
}

class ChunkPlanner {
  static const targetChunkSeconds = 300; // 5 min
  static const snapWindowSeconds = 10;   // search ±10 s for a quiet cut
  static const rmsFrameMs = 20;

  /// [rmsAt] returns the RMS of the frame starting at a given sample, letting
  /// this stay a pure function over the audio rather than owning file I/O.
  static Future<List<Chunk>> plan({
    required int sampleCount,
    required int sampleRate,
    required Future<double> Function(int startSample, int frameSamples) rmsAt,
  });
}
```

Rules, in order:

1. If `sampleCount` fits in one target chunk, return exactly one chunk
   covering the file. (This is what makes the unified path a no-op for short
   recordings.)
2. Otherwise, place a boundary every `targetChunkSeconds`, then move each
   boundary to the lowest-RMS frame within `±snapWindowSeconds`, clamped so
   boundaries stay strictly increasing and inside the file.
3. The final chunk runs to the end and may be shorter.

Chunks are contiguous and non-overlapping: they partition the file exactly,
so no text-level dedupe is needed.

### `packages/stt` — chunked transcription

`transcribeFileInBackground` keeps its isolate but iterates chunks: open the
`WavReader` in the isolate, plan, then for each chunk create an
`OfflineStream`, `acceptWaveform` that window, decode, and collect the text.
Segments are joined with a single space, trimmed.

It gains optional progress reporting:

```dart
Future<Transcript> transcribeFileInBackground(
  String modelDir,
  String wavPath, {
  void Function(double fraction)? onProgress, // 0.0 → 1.0, monotonic
});
```

Progress is `chunksDone / chunksTotal`, so a one-chunk file reports 0 then 1 —
no behaviour change for recordings beyond the new callback being available.

### `apps/mobile` — the import flow

- **Home** gains an Import affordance beside the existing record dock.
- `file_picker` with `FileType.custom` and extensions:
  `m4a, mp3, wav, aac, aiff, caf, flac, ogg, opus, amr, mp4, mov, webm`.
  Platform decoders differ — `webm` in particular is unlikely to decode on
  iOS, and `.mov` is not in `audio_decoder`'s documented list even though
  AVFoundation handles it. Offering a superset and reporting an honest decode
  failure is better than silently hiding formats that would in fact have
  worked; the failure path is already a clear message.
- **`ImportScreen`** mirrors `record_screen`'s shape: convert → transcribe
  with progress → insert the `Meeting` → open it. It owns the two-phase
  progress display ("Converting…" then "Transcribing… 40%").
- `durationMs` comes from `WavReader.duration`. No separate metadata call.

### What this reuses for free

The imported meeting flows into the existing minutes pipeline unchanged, which
means **`SummarizeGate` already covers the silent-import case**: import two
hours of an empty room and Overview says "120 minutes of audio but only 12
words — mostly silence" with a *Summarize anyway* escape hatch, rather than
inventing a meeting. No new work.

## Data flow

```
pick file  (file_picker already stages a readable copy)
  → AudioImporter.toSttWav(picked → app documents)
                                        → imported_<ts>.wav (16 kHz mono)
  → delete file_picker's staged copy
  → WavReader.open() + ChunkPlanner.plan()
  → per-chunk STT in the isolate, progress 0..1
  → Meeting(audioPath: wav, durationMs: reader.duration, transcript,
            status: done)
  → open the meeting → existing minutes pipeline (gated)
```

**Convert straight from the picked path — do not copy the source first.**
`file_picker` already stages a readable copy, and the decoder reads from that
path fine. An extra copy would double transient disk for a large source: a
1 GB `.mp4` would need 1 GB of copy plus the WAV, for no benefit. Only the
converted WAV is kept; `file_picker`'s staged copy is deleted once conversion
succeeds.

## Error handling

| Case | Behaviour |
|---|---|
| Picker cancelled | No-op, no files written |
| Undecodable source (unsupported, DRM, corrupt) | `AudioImportException` → clear message; every partial file deleted |
| Converted WAV fails validation | Surfaced as an error, not transcribed. Signals a converter bug |
| Zero-length / no audio track | Treated as an undecodable source, same message |
| Disk full mid-write | Caught; partials deleted; message names the cause |
| Cancelled mid-import | Isolate torn down, partials deleted, no `Meeting` row |

No `Meeting` row is inserted until transcription succeeds, so a failed import
never leaves a half-meeting in the library.

## Testing

Per `TESTING.md`, tests ship with the slice and run from a fresh clone.

**Unit — `packages/stt/test/wav_reader_test.dart`** (synthesized bytes, no
fixtures, no device)
- valid 16 kHz mono 16-bit header → correct `sampleRate`, `sampleCount`,
  `duration`
- a `LIST` chunk before `data` is skipped correctly (the fixed-offset bug)
- rejects stereo, rejects 8/24/32-bit, rejects non-16 kHz, rejects truncated
  headers and a `data` size exceeding the file
- `readWindow` at offset 0, mid-file, and the exact final sample
- int16 → float conversion at `0`, `32767`, `-32768`
- a window overrunning the end throws rather than reading garbage

**Unit — `packages/stt/test/chunk_planner_test.dart`** (synthetic RMS
callbacks)
- a file shorter than one target chunk → exactly one chunk covering it
- an exact multiple of the target → no zero-length final chunk
- **a loud-silence-loud signal cuts inside the silence**, not at the raw
  target — the test that makes snapping load-bearing
- uniform RMS (no silence) → falls back to the exact target boundary
- chunks partition the file: contiguous, non-overlapping, summing to
  `sampleCount`
- boundaries near the file start/end stay clamped in range

**Unit — chunked transcription** (fake engine)
- N chunks produce their text concatenated in order
- progress is monotonic and ends at 1.0
- a single-chunk file behaves exactly as the current whole-file path

**Widget — `apps/mobile`**
- Import affordance present on Home
- convert-then-transcribe progress states render in order
- a decode failure shows the message and inserts no `Meeting`
- a successful import inserts a `Meeting` with the transcript and opens it
- a `FakeAudioImporter` writes a canned WAV, so app-level tests never invoke
  native decoding

**Regression:** the existing record-flow tests are the safety net for
unifying the transcription path and must pass unchanged.

**Gate:** `melos run analyze` clean, `melos run test` green including the
existing suite.

## Risks

- **`audio_decoder` maturity** — young and low-adoption, in the critical
  path. Mitigated by the interface, MIT licence, and the fork precedent.
- **Chunk artefacts** on continuous speech with no pauses: snapping degrades
  to a fixed cut, clipping at most a word per boundary. Acceptable for
  minutes; Silero VAD (already shipped in `sherpa_onnx` as `vad.dart`) is the
  upgrade path and would additionally unlock silence skipping.
- **Unifying the recording path** touches code verified on the Redmi and the
  iPhone. The existing tests are the guard; device verification is required
  before marking this slice ✅.
- **Large sources** — a 1 GB `.mp4` costs conversion time and transient disk.
  No cap in v1; the progress UI keeps it honest.
- **Tuning constants** — 5 min / ±10 s / 20 ms are estimates, not measured.
  Named constants in one file.
