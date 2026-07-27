import 'package:flutter/material.dart';
import 'package:privoice_core/privoice_core.dart';

import 'animated_in.dart';

/// Editable, checkable, drag-to-reorder action-item list rendered in
/// **stored order**.
///
/// Unlike the old `ActionList` this replaces, done items are not sunk to the
/// bottom — the displayed order always matches [items], so index-based
/// callbacks and the drag handle (via [onReorder]) stay meaningful. Done
/// items keep their existing muted, strikethrough styling; only the
/// auto-sort is gone.
///
/// Reordering uses a nested `ReorderableListView` (`shrinkWrap: true`,
/// `NeverScrollableScrollPhysics`) inside this widget's own `Column`, which
/// itself sits inside the Overview tab's outer scrolling `ListView`. That
/// nesting was the riskiest part of adding drag support; it works cleanly in
/// practice because the inner list never scrolls on its own — dragging past
/// its bounds is a drag, not a scroll, so there is no gesture-arena conflict
/// with the outer scroll view.
///
/// Known limitation, accepted as a product trade-off rather than fixed:
/// because `shrinkWrap: true` gives the inner `ReorderableListView` a
/// `maxScrollExtent` of 0, Flutter's `EdgeDraggingAutoScroller` has nothing
/// to scroll and never reaches up into the outer `OverviewTab` list. So if
/// there are more action items than fit in the visible viewport, dragging an
/// item to the very edge of the screen will **not** auto-scroll the list to
/// reveal items further away — the drag is confined to whatever is already
/// on screen. Typical meetings produce a handful of action items (well
/// within one screen), so this was accepted rather than switching to a
/// reorder-mode toggle with a full-screen reorderable list.
class ActionItemList extends StatelessWidget {
  const ActionItemList({
    super.key,
    required this.items,
    required this.onToggle,
    required this.onEditText,
    required this.onAdd,
    required this.onDelete,
    required this.onReorder,
  });

  final List<ActionItem> items;
  final Future<void> Function(int index, bool done) onToggle;
  final Future<void> Function(int index, String text) onEditText;
  final Future<void> Function(String text) onAdd;
  final Future<void> Function(int index) onDelete;
  final Future<void> Function(int oldIndex, int newIndex) onReorder;

  Future<void> _editItem(BuildContext context, int index) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _ActionItemDialog(
        title: 'Edit action item',
        confirmLabel: 'Save',
        initialText: items[index].text,
      ),
    );
    final text = result?.trim();
    if (text == null || text.isEmpty) return;
    await onEditText(index, text);
  }

  Future<void> _addItem(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const _ActionItemDialog(
        title: 'New action item',
        confirmLabel: 'Add',
        initialText: '',
      ),
    );
    final text = result?.trim();
    if (text == null || text.isEmpty) return;
    await onAdd(text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          // `onReorderItem` (not the deprecated `onReorder`) already applies
          // Flutter's own `if (newIndex > oldIndex) newIndex -= 1;` fix-up
          // before calling this, so [onReorder] here receives the final,
          // already-adjusted insertion index — `_TranscriptScreenState
          // ._reorderItems` no longer has to redo that adjustment itself.
          onReorderItem: onReorder,
          children: [
            for (var i = 0; i < items.length; i++)
              AnimatedIn(
                delayMs: 40 * i,
                key: ValueKey('action-$i'),
                child: Row(children: [
                  ReorderableDragStartListener(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.drag_handle_rounded,
                          color: scheme.onSurfaceVariant),
                    ),
                  ),
                  Checkbox(
                    value: items[i].done,
                    onChanged: (v) => onToggle(i, v ?? false),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _editItem(context, i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          items[i].text,
                          style: TextStyle(
                            color: items[i].done
                                ? scheme.onSurfaceVariant
                                : scheme.onSurface,
                            decoration: items[i].done
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Delete item',
                    onPressed: () => onDelete(i),
                  ),
                ]),
              ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => _addItem(context),
            child: const Text('+ Add item'),
          ),
        ),
      ],
    );
  }
}

/// Add/edit dialog content. Owns its [TextEditingController] so it is
/// disposed by the framework when this widget is actually unmounted (after
/// the dialog's exit animation), not by the caller right after the route
/// pops — same shape as `_RenameDialog` in transcript_screen.dart.
class _ActionItemDialog extends StatefulWidget {
  const _ActionItemDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialText,
  });

  final String title;
  final String confirmLabel;
  final String initialText;

  @override
  State<_ActionItemDialog> createState() => _ActionItemDialogState();
}

class _ActionItemDialogState extends State<_ActionItemDialog> {
  late final _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'Action item'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
