import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/meeting_share.dart';
import 'package:privoice_core/privoice_core.dart';

Meeting _m() => Meeting(
      title: 'Q3 Planning',
      createdAt: DateTime(2026, 7, 10),
      audioPath: '',
      durationMs: 0,
      minutes: '### Summary\nShip in Q3.',
      actionItems: const [
        ActionItem(text: 'Draft spec', done: true),
        ActionItem(text: 'Email Bob'),
      ],
    );

void main() {
  test('actionItemsAsText renders a checkbox list', () {
    final text = actionItemsAsText(_m().actionItems);
    expect(text, '- [x] Draft spec\n- [ ] Email Bob');
  });

  test('actionItemsAsText is empty for no items', () {
    expect(actionItemsAsText(const []), '');
  });

  test('copyAllText includes title, minutes, and action items', () {
    final text = copyAllText(_m());
    expect(text, contains('Q3 Planning'));
    expect(text, contains('Ship in Q3.'));
    expect(text, contains('- [ ] Email Bob'));
  });
}
