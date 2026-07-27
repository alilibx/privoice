import 'dart:math' as math;

/// One contiguous span of samples to transcribe.
class Chunk {
  const Chunk({required this.startSample, required this.sampleCount});

  final int startSample;
  final int sampleCount;

  int get endSample => startSample + sampleCount;
}

/// Splits long audio into transcribable spans, cutting where the audio is
/// quietest so a word is less likely to be severed mid-utterance.
///
/// Chunks partition the audio exactly — contiguous and non-overlapping — so
/// the transcript needs no de-duplication when the pieces are joined.
class ChunkPlanner {
  /// Roughly how long each chunk should be.
  static const int targetChunkSeconds = 300;

  /// How far either side of a target boundary to look for a quiet point.
  static const int snapWindowSeconds = 10;

  /// Granularity of the RMS scan.
  static const int rmsFrameMs = 20;

  static Future<List<Chunk>> plan({
    required int sampleCount,
    required int sampleRate,
    required Future<double> Function(int startSample, int frameSamples) rmsAt,
  }) async {
    if (sampleCount <= 0) return const <Chunk>[];

    final target = targetChunkSeconds * sampleRate;
    if (sampleCount <= target) {
      return [Chunk(startSample: 0, sampleCount: sampleCount)];
    }

    final frame = math.max(1, (rmsFrameMs * sampleRate / 1000).round());
    final snap = snapWindowSeconds * sampleRate;

    final bounds = <int>[0];
    var next = target;
    while (next < sampleCount) {
      final lo = math.max(bounds.last + frame, next - snap);
      final hi = math.min(sampleCount - frame, next + snap);

      var best = math.min(next, sampleCount - 1);
      var bestRms = double.infinity;
      for (var s = lo; s <= hi; s += frame) {
        final rms = await rmsAt(s, frame);
        // `<=` (not `<`): on a tie, prefer the later candidate. With a
        // strict `<`, uniformly loud audio always resolves ties to `lo`,
        // so every boundary drifts backward by a full snap window and
        // chunks systematically shrink, which can silently add an extra
        // chunk to an exact multiple of the target length.
        if (rms <= bestRms) {
          bestRms = rms;
          best = s;
        }
      }

      // Never move backwards; that would produce an empty or negative chunk.
      if (best <= bounds.last) best = math.min(next, sampleCount - 1);

      bounds.add(best);
      next = best + target;
    }
    bounds.add(sampleCount);

    final chunks = <Chunk>[];
    for (var i = 0; i < bounds.length - 1; i++) {
      final len = bounds[i + 1] - bounds[i];
      if (len > 0) {
        chunks.add(Chunk(startSample: bounds[i], sampleCount: len));
      }
    }
    return chunks;
  }
}
