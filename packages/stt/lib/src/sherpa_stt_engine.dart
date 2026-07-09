import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'stt_engine.dart';
import 'transcript.dart';

/// [SttEngine] backed by sherpa-onnx running an offline transducer model
/// (NVIDIA Parakeet-TDT v3 INT8). This is the only file that touches the
/// native binding.
///
/// Verified against sherpa_onnx 1.13.4:
///   initBindings() · OfflineTransducerModelConfig(encoder/decoder/joiner) ·
///   OfflineModelConfig(transducer:, tokens:, ...) · OfflineRecognizer ·
///   createStream()/decode()/getResult().text · readWave() → WaveData.
class SherpaSttEngine implements SttEngine {
  sherpa.OfflineRecognizer? _recognizer;

  @override
  Future<void> init(SttModelPaths paths) async {
    sherpa.initBindings();

    final model = sherpa.OfflineModelConfig(
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

    _recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(model: model),
    );
  }

  @override
  Future<Transcript> transcribe(String wavPath) async {
    final rec = _recognizer;
    if (rec == null) {
      throw StateError('init() must be called before transcribe()');
    }

    final wave = sherpa.readWave(wavPath);
    if (wave.sampleRate == 0) {
      throw StateError('Could not read WAV file: $wavPath');
    }

    final stream = rec.createStream();
    stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
    rec.decode(stream);
    final result = rec.getResult(stream);
    stream.free();

    final durationSec = wave.samples.length / wave.sampleRate;
    return Transcript.fromSegments(
      [
        TranscriptSegment(
          text: result.text,
          startSec: 0.0,
          endSec: durationSec,
        ),
      ],
      Duration(milliseconds: (durationSec * 1000).round()),
    );
  }

  @override
  Future<void> dispose() async {
    _recognizer?.free();
    _recognizer = null;
  }
}
