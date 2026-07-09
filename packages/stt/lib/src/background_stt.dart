import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'stt_engine.dart';
import 'transcript.dart';

/// Sendable request for a one-shot background transcription.
class SttRequest {
  const SttRequest({
    required this.encoder,
    required this.decoder,
    required this.joiner,
    required this.tokens,
    required this.wavPath,
  });

  factory SttRequest.from(SttModelPaths paths, String wavPath) => SttRequest(
        encoder: paths.encoder,
        decoder: paths.decoder,
        joiner: paths.joiner,
        tokens: paths.tokens,
        wavPath: wavPath,
      );

  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;
  final String wavPath;
}

/// Runs the whole init → transcribe → dispose cycle inside a one-shot isolate
/// (via [compute]) so the 622 MB model load and inference never block the UI.
///
/// One-shot keeps it simple for S2 (one transcription per recording); a
/// long-lived isolate that keeps the recognizer warm is a later optimization.
Future<Transcript> transcribeFileInBackground(
  SttModelPaths paths,
  String wavPath,
) {
  return compute(_transcribeSync, SttRequest.from(paths, wavPath));
}

/// Top-level so it can run in the [compute] isolate.
Transcript _transcribeSync(SttRequest req) {
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

  final wave = sherpa.readWave(req.wavPath);
  if (wave.sampleRate == 0) {
    rec.free();
    throw StateError('Could not read WAV file: ${req.wavPath}');
  }

  final stream = rec.createStream();
  stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
  rec.decode(stream);
  final result = rec.getResult(stream);
  stream.free();
  rec.free();

  final durationSec = wave.samples.length / wave.sampleRate;
  return Transcript.fromSegments(
    [
      TranscriptSegment(text: result.text, startSec: 0.0, endSec: durationSec),
    ],
    Duration(milliseconds: (durationSec * 1000).round()),
  );
}
