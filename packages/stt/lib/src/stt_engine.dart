import 'transcript.dart';

/// File paths to the four artifacts of a transducer STT model
/// (Parakeet-TDT / NeMo transducer layout).
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

/// Backend-agnostic speech-to-text contract.
///
/// The UI depends only on this interface; the sherpa-onnx implementation (and,
/// later, any online backend) lives behind it.
abstract class SttEngine {
  Future<void> init(SttModelPaths paths);
  Future<Transcript> transcribe(String wavPath);
  Future<void> dispose();
}
