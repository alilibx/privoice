import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_ai/privoice_ai.dart';

void main() {
  test('strips leading dash/star bullets and trims', () {
    expect(
      parseActionItems('- Ship the beta Friday\n* Finish login Thursday'),
      ['Ship the beta Friday', 'Finish login Thursday'],
    );
  });

  test('drops per-item "None" owner lines (the reported bug)', () {
    // The 1B model interleaves a "None" line (owner placeholder) after items.
    const raw = '- Ship the beta Friday\n'
        '- None\n'
        '- Finish login Thursday\n'
        '- None';
    expect(
      parseActionItems(raw),
      ['Ship the beta Friday', 'Finish login Thursday'],
    );
  });

  test('drops None variants: punctuation, parens, case, N/A', () {
    const raw = '- Real item\n'
        'None.\n'
        '(None)\n'
        'none\n'
        'N/A\n'
        '- NONE';
    expect(parseActionItems(raw), ['Real item']);
  });

  test('handles non-ASCII bullet glyphs the old regex missed', () {
    const raw = '• Email the team\n– None\n· Book the room';
    expect(parseActionItems(raw), ['Email the team', 'Book the room']);
  });

  test('strips ordered-list numbering', () {
    expect(
      parseActionItems('1. First task\n2) Second task'),
      ['First task', 'Second task'],
    );
  });

  test('drops "no action items" style lines and empty input', () {
    expect(parseActionItems('No action items identified.'), isEmpty);
    expect(parseActionItems('   '), isEmpty);
  });

  test('keeps real items that merely contain the word none', () {
    expect(
      parseActionItems('- Leave none of the tickets unassigned'),
      ['Leave none of the tickets unassigned'],
    );
  });
}
