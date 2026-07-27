/// Why a transcript was judged unsuitable for summarizing.
enum GateOutcome {
  /// Substantial enough to summarize.
  sufficient,

  /// Fewer than [SummarizeGate.minWords] words in total.
  tooFewWords,

  /// Long recording, very little speech — mostly silence.
  tooSparse,
}

/// The gate's answer, carrying the numbers the UI quotes back to the user.
class GateVerdict {
  const GateVerdict({
    required this.outcome,
    required this.wordCount,
    required this.wordsPerMinute,
  });

  final GateOutcome outcome;
  final int wordCount;

  /// Speech rate, or 0 when the duration is unknown/non-positive.
  final double wordsPerMinute;

  bool get sufficient => outcome == GateOutcome.sufficient;
}

/// Decides whether a transcript has enough substance to summarize.
///
/// Exists because an LLM asked to summarize four words will not decline — it
/// invents a plausible meeting. A 13-second recording that transcribed to
/// "So is it working?" produced minutes with three key points, a decision to
/// proceed to deployment, and four action items, none of which happened.
/// Refusing is the honest answer, so the decision is made here, before any
/// inference runs.
class SummarizeGate {
  /// Below this many words, there is nothing to summarize.
  static const int minWords = 30;

  /// Below this rate, a recording is mostly silence.
  static const int minWordsPerMinute = 20;

  /// The rate rule only applies to recordings at least this long, so a short,
  /// deliberately dense voice note is judged on word count alone.
  static const int densityFloorMs = 60000;

  static GateVerdict assess({
    required String transcript,
    required int durationMs,
  }) {
    final words = transcript.split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    final minutes = durationMs > 0 ? durationMs / 60000 : 0.0;
    final wpm = minutes > 0 ? words / minutes : 0.0;

    if (words < minWords) {
      return GateVerdict(
        outcome: GateOutcome.tooFewWords,
        wordCount: words,
        wordsPerMinute: wpm,
      );
    }
    if (durationMs >= densityFloorMs && wpm < minWordsPerMinute) {
      return GateVerdict(
        outcome: GateOutcome.tooSparse,
        wordCount: words,
        wordsPerMinute: wpm,
      );
    }
    return GateVerdict(
      outcome: GateOutcome.sufficient,
      wordCount: words,
      wordsPerMinute: wpm,
    );
  }
}
