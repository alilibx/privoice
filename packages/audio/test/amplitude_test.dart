import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_audio/privoice_audio.dart';

void main() {
  test('normalizeAmplitude maps dBFS to 0..1', () {
    expect(normalizeAmplitude(0), 1.0);
    expect(normalizeAmplitude(-50), 0.0);
    expect(normalizeAmplitude(-25), closeTo(0.5, 1e-9));
    expect(normalizeAmplitude(-160), 0.0); // clamped below floor
    expect(normalizeAmplitude(10), 1.0); // clamped above 0 dBFS
  });
}
