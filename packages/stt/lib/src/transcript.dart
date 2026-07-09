/// A contiguous span of recognized speech with rough start/end times.
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

/// The result of transcribing one audio file.
class Transcript {
  const Transcript({
    required this.segments,
    required this.fullText,
    required this.audioDuration,
  });

  final List<TranscriptSegment> segments;
  final String fullText;
  final Duration audioDuration;

  /// Builds a [Transcript], deriving [fullText] by trimming each segment and
  /// joining the non-empty ones with a single space.
  factory Transcript.fromSegments(
    List<TranscriptSegment> segments,
    Duration audioDuration,
  ) {
    final text = segments
        .map((s) => s.text.trim())
        .where((s) => s.isNotEmpty)
        .join(' ');
    return Transcript(
      segments: segments,
      fullText: text,
      audioDuration: audioDuration,
    );
  }
}
