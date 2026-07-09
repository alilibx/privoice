import 'package:record/record.dart';

/// Capture settings for meeting audio: 16 kHz mono WAV — the input format
/// on-device STT models (Parakeet/Whisper) expect.
class RecordingConfig {
  const RecordingConfig({
    this.sampleRate = 16000,
    this.numChannels = 1,
    this.encoder = AudioEncoder.wav,
  });

  final int sampleRate;
  final int numChannels;
  final AudioEncoder encoder;

  /// Deterministic file name derived from a timestamp, so a recording maps to
  /// exactly one file path.
  String fileName(DateTime now) => 'meeting_${now.millisecondsSinceEpoch}.wav';

  RecordConfig toRecordConfig() => RecordConfig(
        encoder: encoder,
        sampleRate: sampleRate,
        numChannels: numChannels,
      );
}
