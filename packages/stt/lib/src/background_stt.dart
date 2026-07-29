import 'dart:isolate';
import 'dart:math' as math;

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

/// The signature of [transcribeFileInBackground].
///
/// Exists so a caller can hold transcription as a dependency instead of calling
/// the top-level function directly: the real one spawns a `compute` isolate,
/// which cannot complete against a widget test's fake clock, so any screen that
/// hard-codes it is untestable.
typedef FileTranscriber = Future<Transcript> Function(
  SttModelPaths paths,
  String wavPath, {
  void Function(double fraction)? onProgress,
});

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

      // The stream holds native heap (tens of MB) and is derived from `rec`, so
      // it must be freed even when a chunk throws — otherwise the leak survives
      // to the next chunk, and the outer `finally` frees the recognizer while a
      // live stream still points at it.
      final stream = rec.createStream();
      final String text;
      try {
        stream.acceptWaveform(samples: samples, sampleRate: r.sampleRate);
        rec.decode(stream);
        text = rec.getResult(stream).text;
      } finally {
        stream.free();
      }

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
