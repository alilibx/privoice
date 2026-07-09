import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_ai/privoice_ai.dart';

void main() {
  test('reduce prompt asks for the four sections and includes the notes', () {
    final p = Prompts.reduce('note one\nnote two', null);
    expect(p, contains('Summary'));
    expect(p, contains('Decisions'));
    expect(p, contains('Action items'));
    expect(p, contains('note one'));
  });

  test('summarizeWhole weaves in user instructions when provided', () {
    final p = Prompts.summarizeWhole('transcript', 'focus on risks');
    expect(p, contains('focus on risks'));
    expect(p, contains('transcript'));
  });

  test('summarizeWhole omits instruction clause when none given', () {
    final p = Prompts.summarizeWhole('transcript', null);
    expect(p, isNot(contains('specifically wants')));
  });

  test('actionItems prompt requests one item per line', () {
    expect(Prompts.actionItems('t'), contains('one action item per line'));
  });
}
