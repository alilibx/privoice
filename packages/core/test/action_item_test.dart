import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_core/privoice_core.dart';

void main() {
  test('toJson/fromJson round-trips text and done', () {
    const a = ActionItem(text: 'Ship the beta', done: true);
    final back = ActionItem.fromJson(a.toJson());
    expect(back.text, 'Ship the beta');
    expect(back.done, isTrue);
  });

  test('defaults done to false', () {
    const a = ActionItem(text: 'x');
    expect(a.done, isFalse);
  });

  test('fromJson tolerates a missing done key', () {
    final a = ActionItem.fromJson({'text': 'legacy'});
    expect(a.done, isFalse);
  });

  test('copyWith flips done only', () {
    const a = ActionItem(text: 'x');
    final b = a.copyWith(done: true);
    expect(b.text, 'x');
    expect(b.done, isTrue);
  });

  test('value equality', () {
    expect(const ActionItem(text: 'x'), const ActionItem(text: 'x'));
    expect(const ActionItem(text: 'x', done: true),
        isNot(const ActionItem(text: 'x')));
  });
}
