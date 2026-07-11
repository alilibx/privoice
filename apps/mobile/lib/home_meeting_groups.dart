import 'package:privoice_core/privoice_core.dart';

/// A labelled bucket of meetings for the Home list.
class MeetingGroup {
  const MeetingGroup(this.label, this.meetings);
  final String label;
  final List<Meeting> meetings;
}

const _weekday = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _month = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

/// Group [meetings] (newest first) into Today / This week / Earlier relative to
/// [now]. Empty buckets are omitted.
List<MeetingGroup> groupMeetings(List<Meeting> meetings, DateTime now) {
  final startOfToday = DateTime(now.year, now.month, now.day);
  final weekAgo = startOfToday.subtract(const Duration(days: 7));
  final sorted = [...meetings]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final today = <Meeting>[], week = <Meeting>[], earlier = <Meeting>[];
  for (final m in sorted) {
    if (!m.createdAt.isBefore(startOfToday)) {
      today.add(m);
    } else if (!m.createdAt.isBefore(weekAgo)) {
      week.add(m);
    } else {
      earlier.add(m);
    }
  }
  return [
    if (today.isNotEmpty) MeetingGroup('Today', today),
    if (week.isNotEmpty) MeetingGroup('This week', week),
    if (earlier.isNotEmpty) MeetingGroup('Earlier', earlier),
  ];
}

/// Human relative time: "15m ago" / "2h ago" today, weekday within the last
/// week, "1 Jun" older.
String relativeLabel(DateTime createdAt, DateTime now) {
  final startOfToday = DateTime(now.year, now.month, now.day);
  if (!createdAt.isBefore(startOfToday)) {
    final diff = now.difference(createdAt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
  final weekAgo = startOfToday.subtract(const Duration(days: 7));
  if (!createdAt.isBefore(weekAgo)) return _weekday[createdAt.weekday - 1];
  return '${createdAt.day} ${_month[createdAt.month - 1]}';
}

/// mm:ss from milliseconds.
String formatDuration(int ms) {
  final s = ms ~/ 1000;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// The one-line meta shown under a meeting title.
String metaLine(Meeting m, DateTime now) {
  final rel = relativeLabel(m.createdAt, now);
  if (m.status == MeetingStatus.transcribing) return '$rel · transcribing…';
  if (m.status == MeetingStatus.failed) return '$rel · failed';
  final parts = <String>[rel, formatDuration(m.durationMs)];
  if ((m.minutes ?? '').isNotEmpty) parts.add('Minutes');
  if (m.actionItems.isNotEmpty) parts.add('${m.actionItems.length} actions');
  return parts.join(' · ');
}
