import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_core/privoice_core.dart';

void main() {
  test('toRow/fromRow round-trips all fields', () {
    final m = Meeting(
      id: 7,
      title: 'Sprint planning',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1720000000000),
      audioPath: '/audio/x.wav',
      durationMs: 123456,
      transcript: 'hello world',
      minutes: '### Summary\nok',
      actionItems: const ['a', 'b'],
      status: MeetingStatus.done,
    );

    final back = Meeting.fromRow(m.toRow());

    expect(back.id, 7);
    expect(back.title, 'Sprint planning');
    expect(back.createdAt, m.createdAt);
    expect(back.audioPath, '/audio/x.wav');
    expect(back.durationMs, 123456);
    expect(back.transcript, 'hello world');
    expect(back.minutes, '### Summary\nok');
    expect(back.actionItems, ['a', 'b']);
    expect(back.status, MeetingStatus.done);
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
}
