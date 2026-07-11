import 'package:privoice_core/privoice_core.dart';

/// Action items as a Markdown-style checklist ("- [x]"/"- [ ]"), or '' if none.
String actionItemsAsText(List<ActionItem> items) => items
    .map((a) => '- [${a.done ? 'x' : ' '}] ${a.text}')
    .join('\n');

/// Everything worth copying: title, minutes, and the action checklist.
String copyAllText(Meeting m) {
  final parts = <String>[m.title];
  final minutes = (m.minutes ?? '').trim();
  if (minutes.isNotEmpty) parts.add(minutes);
  final items = actionItemsAsText(m.actionItems);
  if (items.isNotEmpty) parts.add('Action items\n$items');
  return parts.join('\n\n');
}
