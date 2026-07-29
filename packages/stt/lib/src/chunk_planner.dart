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

  /// Shortest chunk worth handing to the recognizer; anything shorter is
  /// merged into its predecessor instead of being emitted.
  ///
  /// This exists because the RMS scan is clamped to `sampleCount - frame` so it
  /// never reads past the end of the file, which lets the last boundary land as
  /// little as one [rmsFrameMs] frame — 320 samples, 20 ms — before EOF. A file
  /// of `target + 1` samples, or one whose quietest frame is its last, would
  /// then end on a 320-sample chunk. At 16 kHz a feature extractor with a 25 ms
  /// window and 10 ms hop yields *zero* frames from 20 ms of audio, so the
  /// encoder is handed an empty feature matrix: at best a wasted decode and an
  /// empty segment, at worst a native throw inside the isolate that discards
  /// the entire transcription after all the work is done.
  ///
  /// One second is the floor because no shorter span can carry a recognisable
  /// word; merging costs at most one extra second on the preceding chunk, which
  /// changes neither peak memory nor cut quality in any meaningful way.
  static const int minChunkSeconds = 1;

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
      var bestDist = (best - next).abs();
      for (var s = lo; s <= hi; s += frame) {
        final rms = await rmsAt(s, frame);
        final dist = (s - next).abs();
        // Lowest RMS wins outright — a genuine silence always beats
        // proximity to the target. On a tie (e.g. uniformly loud audio,
        // where no candidate is quieter than any other), prefer whichever
        // candidate is closest to the raw target offset, rather than
        // whichever end of the scan window happened to be checked first or
        // last. Without this, a strict `<` always resolves ties to `lo`
        // (boundary drifts back a full snap window, shrinking chunks and
        // silently adding an extra one to an exact multiple of the target
        // length) and a bare `<=` always resolves ties to `hi` (boundary
        // drifts forward a full snap window instead of landing on target).
        if (rms < bestRms || (rms == bestRms && dist < bestDist)) {
          bestRms = rms;
          bestDist = dist;
          best = s;
        }
      }

      // Never move backwards; that would produce an empty or negative chunk.
      if (best <= bounds.last) best = math.min(next, sampleCount - 1);

      bounds.add(best);
      next = best + target;
    }

    // Drop trailing boundaries that would leave a chunk below the floor, which
    // merges the offcut into its predecessor. See [minChunkSeconds] for why a
    // 20 ms tail is not merely wasteful but a hazard. Only the last chunk can
    // ever be this short — interior boundaries are at least `target - snap`
    // apart — but the loop is written to hold regardless.
    final minChunk = minChunkSeconds * sampleRate;
    while (bounds.length > 1 && sampleCount - bounds.last < minChunk) {
      bounds.removeLast();
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
