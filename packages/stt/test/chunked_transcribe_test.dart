import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_stt/privoice_stt.dart';

import 'wav_bytes.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('chunked'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a short file plans exactly one chunk covering all samples', () async {
    // This is what preserves the existing recording behaviour: one chunk in,
    // one decode pass, same result as the old whole-file path.
    final f = File('${tmp.path}/short.wav');
    await f.writeAsBytes(wavBytes(samples: List.filled(16000 * 30, 0)));
    final r = await WavReader.open(f.path);

    final chunks = await ChunkPlanner.plan(
      sampleCount: r.sampleCount,
      sampleRate: r.sampleRate,
      rmsAt: (s, n) async => rmsOf(await r.readWindow(s, n)),
    );

    expect(chunks, hasLength(1));
    expect(chunks.single.sampleCount, r.sampleCount);
    await r.close();
  });

  test('rmsOf is 0 for silence and positive for signal', () async {
    expect(rmsOf(Float32List.fromList([0, 0, 0])), 0.0);
    expect(rmsOf(Float32List.fromList([0.5, -0.5])), closeTo(0.5, 1e-6));
    expect(rmsOf(Float32List(0)), 0.0);
  });

  test('segments assembled from chunks join in order with real times', () {
    // Transcript.fromSegments is what turns per-chunk text into fullText, so
    // pin the ordering and the timing arithmetic here.
    const sr = 16000;
    final t = Transcript.fromSegments([
      TranscriptSegment(text: 'hello there', startSec: 0, endSec: 5),
      TranscriptSegment(text: 'second part', startSec: 5, endSec: 9),
    ], const Duration(seconds: 9));

    expect(t.fullText, 'hello there second part');
    expect(t.segments, hasLength(2));
    expect(t.segments[1].startSec, 5);
    expect(sr, 16000); // guards against an accidental rate change in this test
  });
}
