import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_ai/privoice_ai.dart';

void main() {
  test('short transcript is one chunk and does not need map-reduce', () {
    const t = 'hello world this is short';
    expect(needsMapReduce(t, wordsPerChunk: 700), isFalse);
    expect(chunkTranscript(t, wordsPerChunk: 700), [t]);
  });

  test('long transcript splits into word-bounded chunks', () {
    final words = List.generate(1600, (i) => 'w$i').join(' ');
    expect(needsMapReduce(words, wordsPerChunk: 700), isTrue);
    final chunks = chunkTranscript(words, wordsPerChunk: 700);
    expect(chunks.length, 3); // 700 + 700 + 200
    expect(chunks.first.split(' ').length, 700);
    expect(chunks.last.split(' ').length, 200);
  });

  test('empty transcript yields no chunks', () {
    expect(chunkTranscript('   '), isEmpty);
  });
}
