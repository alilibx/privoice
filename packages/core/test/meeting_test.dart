import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_core/privoice_core.dart';

void main() {
  test('toRow/fromRow round-trips all fields incl. action items', () {
    final m = Meeting(
      id: 7,
      title: 'Sprint planning',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1720000000000),
      audioPath: '/audio/x.wav',
      durationMs: 123456,
      transcript: 'hello world',
      minutes: '### Summary\nok',
      actionItems: const [
        ActionItem(text: 'a', done: true),
        ActionItem(text: 'b'),
      ],
      status: MeetingStatus.done,
    );

    final back = Meeting.fromRow(m.toRow());

    expect(back.title, 'Sprint planning');
    expect(back.minutes, '### Summary\nok');
    expect(back.actionItems, const [
      ActionItem(text: 'a', done: true),
      ActionItem(text: 'b'),
    ]);
    expect(back.status, MeetingStatus.done);
  });

  test('action items serialize as a JSON array', () {
    final m = Meeting(
      title: 'x',
      audioPath: '',
      durationMs: 0,
      actionItems: const [ActionItem(text: 'a')],
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
    final raw = m.toRow()['action_items'] as String;
    expect(jsonDecode(raw), [
      {'text': 'a', 'done': false}
    ]);
  });

  test('empty action items serialize to null and back to []', () {
    final m = Meeting(
      title: 'x',
      audioPath: '',
      durationMs: 0,
      actionItems: const [],
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
    expect(m.toRow()['action_items'], isNull);
    expect(Meeting.fromRow(m.toRow()).actionItems, isEmpty);
  });

  test('fromRow falls back to legacy newline action_items', () {
    final row = {
      'id': 1,
      'title': 'Legacy',
      'created_at': 0,
      'audio_path': '/a.wav',
      'duration_ms': 0,
      'transcript': 't',
      'minutes': null,
      'action_items': 'do a\ndo b',
      'status': 'done',
    };
    final m = Meeting.fromRow(row);
    expect(m.actionItems,
        const [ActionItem(text: 'do a'), ActionItem(text: 'do b')]);
  });

  test('fromRow legacy fallback tolerates a line starting with "["', () {
    final row = {
      'id': 1,
      'title': 'Legacy',
      'created_at': 0,
      'audio_path': '/a.wav',
      'duration_ms': 0,
      'transcript': 't',
      'minutes': null,
      'action_items': '[urgent] call the vendor\ndo b',
      'status': 'done',
    };
    final m = Meeting.fromRow(row);
    expect(m.actionItems, const [
      ActionItem(text: '[urgent] call the vendor'),
      ActionItem(text: 'do b'),
    ]);
  });

  group('minutesEditedAt', () {
    Meeting base() => Meeting(
          id: 1,
          title: 'Product sync',
          createdAt: DateTime(2026, 7, 27, 9, 30),
          audioPath: '/tmp/a.wav',
          durationMs: 60000,
          transcript: 'hello',
        );

    test('defaults to null and round-trips as null', () {
      final m = base();
      expect(m.minutesEditedAt, isNull);
      expect(m.toRow()['minutes_edited_at'], isNull);
      expect(Meeting.fromRow(m.toRow()).minutesEditedAt, isNull);
    });

    test('round-trips a timestamp through toRow/fromRow', () {
      final stamp = DateTime(2026, 7, 27, 10, 15);
      final m = base().copyWith(minutesEditedAt: stamp);
      expect(m.toRow()['minutes_edited_at'], stamp.millisecondsSinceEpoch);
      expect(Meeting.fromRow(m.toRow()).minutesEditedAt, stamp);
    });

    test('copyWith without the arg preserves an existing stamp', () {
      final stamp = DateTime(2026, 7, 27, 10, 15);
      final m = base().copyWith(minutesEditedAt: stamp);
      expect(m.copyWith(title: 'Renamed').minutesEditedAt, stamp);
    });

    test('resetMinutesEdited clears the stamp', () {
      final m = base().copyWith(minutesEditedAt: DateTime(2026, 7, 27));
      expect(m.copyWith(resetMinutesEdited: true).minutesEditedAt, isNull);
    });
  });
}
