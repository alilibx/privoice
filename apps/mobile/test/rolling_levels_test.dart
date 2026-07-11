import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/rolling_levels.dart';

void main() {
  test('keeps at most capacity samples, oldest dropped, order preserved', () {
    final r = RollingLevels(3);
    expect(r.samples, isEmpty);
    r.push(0.1);
    r.push(0.2);
    expect(r.samples, [0.1, 0.2]);
    r.push(0.3);
    r.push(0.4); // overflows; 0.1 drops
    expect(r.samples, [0.2, 0.3, 0.4]);
    expect(r.samples.length, 3);
  });

  test('samples is not externally mutable', () {
    final r = RollingLevels(2)..push(0.5);
    expect(() => r.samples.add(9), throwsUnsupportedError);
  });
}
