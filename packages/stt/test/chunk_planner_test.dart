import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_stt/privoice_stt.dart';

const sr = 16000;
const target = ChunkPlanner.targetChunkSeconds * sr;

/// RMS that is loud everywhere — no natural cut point.
Future<double> uniform(int start, int frame) async => 0.5;

void main() {
  group('ChunkPlanner.plan', () {
    test('a file shorter than one target chunk is a single chunk', () async {
      final chunks = await ChunkPlanner.plan(
          sampleCount: 30 * sr, sampleRate: sr, rmsAt: uniform);
      expect(chunks, hasLength(1));
      expect(chunks.single.startSample, 0);
      expect(chunks.single.sampleCount, 30 * sr);
    });

    test('exactly one target chunk stays a single chunk', () async {
      final chunks = await ChunkPlanner.plan(
          sampleCount: target, sampleRate: sr, rmsAt: uniform);
      expect(chunks, hasLength(1));
    });

    test('empty audio yields no chunks', () async {
      expect(
          await ChunkPlanner.plan(
              sampleCount: 0, sampleRate: sr, rmsAt: uniform),
          isEmpty);
    });

    test('chunks partition the audio exactly', () async {
      final total = (target * 3.4).round();
      final chunks = await ChunkPlanner.plan(
          sampleCount: total, sampleRate: sr, rmsAt: uniform);

      expect(chunks.first.startSample, 0);
      expect(chunks.last.endSample, total);
      var covered = 0;
      for (var i = 0; i < chunks.length; i++) {
        expect(chunks[i].sampleCount, greaterThan(0));
        if (i > 0) {
          // contiguous, no gap and no overlap
          expect(chunks[i].startSample, chunks[i - 1].endSample);
        }
        covered += chunks[i].sampleCount;
      }
      expect(covered, total);
    });

    test('an exact multiple produces no zero-length final chunk', () async {
      final chunks = await ChunkPlanner.plan(
          sampleCount: target * 2, sampleRate: sr, rmsAt: uniform);
      expect(chunks, hasLength(2));
      for (final c in chunks) {
        expect(c.sampleCount, greaterThan(0));
      }
    });

    test('cuts inside a silent gap rather than at the raw target', () async {
      // Silence from target+2s to target+4s. The planner should move the
      // boundary into it instead of cutting at exactly `target`.
      const gapStart = target + 2 * sr;
      const gapEnd = target + 4 * sr;
      Future<double> loudWithGap(int start, int frame) async =>
          (start >= gapStart && start < gapEnd) ? 0.0 : 0.8;

      final chunks = await ChunkPlanner.plan(
          sampleCount: target * 2, sampleRate: sr, rmsAt: loudWithGap);

      expect(chunks.length, greaterThanOrEqualTo(2));
      final boundary = chunks[0].endSample;
      expect(boundary, greaterThanOrEqualTo(gapStart));
      expect(boundary, lessThan(gapEnd));
    });

    test('with no silence, the boundary stays at the target', () async {
      final chunks = await ChunkPlanner.plan(
          sampleCount: target * 2, sampleRate: sr, rmsAt: uniform);
      // Uniform RMS: the first candidate wins, which is the earliest offset in
      // the search window, so the boundary must land within the snap window.
      final boundary = chunks[0].endSample;
      expect((boundary - target).abs(),
          lessThanOrEqualTo(ChunkPlanner.snapWindowSeconds * sr));
    });

    test('boundaries never fall outside the audio', () async {
      final total = target + 3 * sr; // second chunk shorter than the window
      final chunks = await ChunkPlanner.plan(
          sampleCount: total, sampleRate: sr, rmsAt: uniform);
      for (final c in chunks) {
        expect(c.startSample, greaterThanOrEqualTo(0));
        expect(c.endSample, lessThanOrEqualTo(total));
      }
      expect(chunks.last.endSample, total);
    });
  });
}
