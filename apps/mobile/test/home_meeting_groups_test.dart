import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/home_meeting_groups.dart';
import 'package:privoice_core/privoice_core.dart';

Meeting _m(DateTime at, {int ms = 60000, MeetingStatus status = MeetingStatus.done, String? minutes, List<ActionItem> actions = const []}) =>
    Meeting(title: 't', createdAt: at, audioPath: '', durationMs: ms, status: status, minutes: minutes, actionItems: actions);

void main() {
  final now = DateTime(2026, 7, 11, 10, 0);

  group('groupMeetings', () {
    test('buckets into Today / This week / Earlier, newest first, empties omitted', () {
      final today = _m(DateTime(2026, 7, 11, 8));
      final week = _m(DateTime(2026, 7, 8, 9)); // 3 days ago
      final earlier = _m(DateTime(2026, 6, 1));
      final groups = groupMeetings([week, earlier, today], now);
      expect(groups.map((g) => g.label).toList(), ['Today', 'This week', 'Earlier']);
      expect(groups[0].meetings.single.createdAt, today.createdAt);
    });

    test('boundaries: midnight today is Today; 7 days ago is This week; 8 days ago is Earlier', () {
      final midnight = _m(DateTime(2026, 7, 11)); // start of today
      final sevenDays = _m(DateTime(2026, 7, 4)); // exactly 7 days before start-of-today
      final eightDays = _m(DateTime(2026, 7, 3));
      final groups = groupMeetings([midnight, sevenDays, eightDays], now);
      expect(groups[0].label, 'Today');
      expect(groups[1].label, 'This week');
      expect(groups[1].meetings.single.createdAt, sevenDays.createdAt);
      expect(groups[2].label, 'Earlier');
    });

    test('only one bucket → only that group returned', () {
      expect(groupMeetings([_m(DateTime(2026, 1, 1))], now).map((g) => g.label).toList(), ['Earlier']);
      expect(groupMeetings([], now), isEmpty);
    });
  });

  group('relativeLabel', () {
    test('today shows minutes/hours, just now under a minute', () {
      expect(relativeLabel(DateTime(2026, 7, 11, 9, 0), now), '1h ago');
      expect(relativeLabel(DateTime(2026, 7, 11, 9, 45), now), '15m ago');
      expect(relativeLabel(DateTime(2026, 7, 11, 9, 59, 40), now), 'just now');
    });
    test('this week shows weekday, older shows day + month', () {
      expect(relativeLabel(DateTime(2026, 7, 8, 9), now), 'Wed'); // 2026-07-08 is a Wednesday
      expect(relativeLabel(DateTime(2026, 6, 1), now), '1 Jun');
    });
  });

  group('metaLine', () {
    test('done meeting lists time, duration, and available outputs', () {
      final m = _m(DateTime(2026, 7, 11, 9), ms: 132000, minutes: '# x', actions: const [ActionItem(text: 'a'), ActionItem(text: 'b')]);
      expect(metaLine(m, now), '1h ago · 2:12 · Minutes · 2 actions');
    });
    test('transcribing and failed short-circuit', () {
      expect(metaLine(_m(DateTime(2026, 7, 11, 9), status: MeetingStatus.transcribing), now), '1h ago · transcribing…');
      expect(metaLine(_m(DateTime(2026, 7, 11, 9), status: MeetingStatus.failed), now), '1h ago · failed');
    });
  });
}
