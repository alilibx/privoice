import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'stt_engine.dart';
import 'transcript.dart';

/// BENCHMARK AND INTEGRATION-TEST HARNESS ONLY — do not use in an app flow.
///
/// [transcribe] calls `sherpa.readWave()`, which materialises the **entire**
/// audio file as a `Float32List`: roughly 230 MB of RAM per hour of 16 kHz mono
/// audio, on top of the ~1.4 GB of models already resident. A two-hour import
/// would be killed by jetsam on a 4 GB device. That is exactly the failure the
/// chunked path was built to eliminate.
///
/// **The supported path is `transcribeFileInBackground` in `background_stt.dart`**,
/// which reads bounded windows via `WavReader` and transcribes spans planned by
/// `ChunkPlanner`, so peak memory is independent of file length.
///
/// This class is deliberately retained (see STATUS.md, "Spike harness
/// retained") because `tools/emulator-stt-test.sh`,
/// `tools/fetch-and-push-model.sh`, `integration_test/stt_pipeline_test.dart`
/// and `docs/superpowers/benchmarks/2026-07-09-stt-spike-results.md` all depend
/// on it to re-run the on-device STT benchmark and to prove the native FFI path
/// works end to end. Deleting it would break those; wiring it into a user-facing
/// flow would reintroduce the out-of-memory bug. If you need STT in a feature,
/// use `transcribeFileInBackground`.
///
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
