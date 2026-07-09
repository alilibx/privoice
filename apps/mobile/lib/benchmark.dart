/// The go/no-go number for the STT spike: how transcription time compares to
/// the audio's real duration (real-time factor).
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
