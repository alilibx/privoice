import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_ai/privoice_ai.dart';

/// Builds a transcript with exactly [n] whitespace-separated words.
String _words(int n) => List.generate(n, (i) => 'word$i').join(' ');

void main() {
  group('SummarizeGate.assess', () {
    test('empty transcript is tooFewWords', () {
      final v = SummarizeGate.assess(transcript: '', durationMs: 60000);
      expect(v.outcome, GateOutcome.tooFewWords);
      expect(v.sufficient, isFalse);
      expect(v.wordCount, 0);
    });

    test('whitespace-only transcript is tooFewWords', () {
      final v =
          SummarizeGate.assess(transcript: '   \n\t  ', durationMs: 60000);
      expect(v.outcome, GateOutcome.tooFewWords);
      expect(v.wordCount, 0);
    });

    // The real regression: the iOS bring-up recorded 13s that transcribed to
    // "So is it working?" and the app invented a full meeting from it.
    test('the "So is it working?" case is tooFewWords', () {
      final v = SummarizeGate.assess(
          transcript: 'So is it working?', durationMs: 13000);
      expect(v.outcome, GateOutcome.tooFewWords);
      expect(v.wordCount, 4);
    });

    test('29 words is blocked, 30 and 31 are sufficient', () {
      expect(SummarizeGate.assess(transcript: _words(29), durationMs: 30000)
          .outcome, GateOutcome.tooFewWords);
      expect(SummarizeGate.assess(transcript: _words(30), durationMs: 30000)
          .outcome, GateOutcome.sufficient);
      expect(SummarizeGate.assess(transcript: _words(31), durationMs: 30000)
          .outcome, GateOutcome.sufficient);
    });

    test('40 words over 18 minutes is tooSparse', () {
      final v = SummarizeGate.assess(
          transcript: _words(40), durationMs: 18 * 60 * 1000);
      expect(v.outcome, GateOutcome.tooSparse);
      expect(v.wordsPerMinute, closeTo(2.22, 0.01));
    });

    test('40 words over 15 seconds is sufficient (below the density floor)',
        () {
      final v =
          SummarizeGate.assess(transcript: _words(40), durationMs: 15000);
      expect(v.outcome, GateOutcome.sufficient);
    });

    test('at the density floor exactly, the rate rule applies', () {
      // 30 words in 60s = 30 wpm, clears the 20 wpm bar.
      expect(
          SummarizeGate.assess(
                  transcript: _words(30), durationMs: SummarizeGate.densityFloorMs)
              .outcome,
          GateOutcome.sufficient);
      // The word rule is checked first, so 10 words is tooFewWords, not tooSparse.
      expect(
          SummarizeGate.assess(
                  transcript: _words(10), durationMs: SummarizeGate.densityFloorMs)
              .outcome,
          GateOutcome.tooFewWords);
    });

    test('durationMs of 0 skips the density rule instead of dividing by zero',
        () {
      final v = SummarizeGate.assess(transcript: _words(30), durationMs: 0);
      expect(v.outcome, GateOutcome.sufficient);
      expect(v.wordsPerMinute, 0);
    });

    test('negative durationMs is treated like zero', () {
      final v = SummarizeGate.assess(transcript: _words(30), durationMs: -5);
      expect(v.outcome, GateOutcome.sufficient);
    });

    test('reports wordCount and wordsPerMinute for UI copy', () {
      final v =
          SummarizeGate.assess(transcript: _words(120), durationMs: 120000);
      expect(v.wordCount, 120);
      expect(v.wordsPerMinute, closeTo(60, 0.01));
    });

    test('collapses irregular whitespace when counting', () {
      final v = SummarizeGate.assess(
          transcript: 'one   two\n\nthree\tfour  ', durationMs: 0);
      expect(v.wordCount, 4);
    });
  });
}
