import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/benchmark.dart';

void main() {
  test('rtf is transcribe time over audio time', () {
    final r = BenchmarkResult.compute(audioMs: 10000, transcribeMs: 2500);
    expect(r.rtf, 0.25);
  });

  test('describe flags faster-than-realtime and includes rtf', () {
    final r = BenchmarkResult.compute(audioMs: 10000, transcribeMs: 2500);
    expect(r.describe(), contains('0.25'));
    expect(r.describe(), contains('faster than realtime'));
  });

  test('describe flags slower-than-realtime', () {
    final r = BenchmarkResult.compute(audioMs: 10000, transcribeMs: 15000);
    expect(r.describe(), contains('SLOWER than realtime'));
  });
}
