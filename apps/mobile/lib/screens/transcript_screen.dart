import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:privoice_ai/privoice_ai.dart';
import 'package:privoice_core/privoice_core.dart';
import 'package:share_plus/share_plus.dart';

import '../ai_service.dart';
import '../meeting_share.dart';
import '../model_manager.dart';
import '../widgets/ask_sheet.dart';
import 'minutes_editor_screen.dart';
import 'overview_tab.dart';

/// Matches the placeholder title from record_screen._defaultTitle()
/// ("Meeting D/M HH:MM"). Auto-title only overwrites titles of this shape.
final _defaultTitlePattern =
    RegExp(r'^Meeting \d{1,2}/\d{1,2} \d{2}:\d{2}$');

bool isDefaultMeetingTitle(String title) =>
    _defaultTitlePattern.hasMatch(title.trim());

/// Meeting screen: Overview (AI minutes + action items) + raw Transcript.
class TranscriptScreen extends StatefulWidget {
  const TranscriptScreen({
    super.key,
    required this.meeting,
    required this.repository,
    required this.ai,
    this.modelManager,
  });

  final Meeting meeting;
  final MeetingRepository repository;
  final AiService ai;
  final ModelManager? modelManager;

  @override
  State<TranscriptScreen> createState() => _TranscriptScreenState();
}

class _TranscriptScreenState extends State<TranscriptScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late Meeting _meeting;

  bool _busy = false;
  bool _autoStarted = false;
  bool _genFailed = false;
  String _busyLabel = '';
  double _progress = 0;
  String _streaming = '';

  ModelManager get _manager => widget.modelManager ?? ModelManager.instance;

  @override
  void initState() {
    super.initState();
    _meeting = widget.meeting;
    _tabs = TabController(length: 2, vsync: this); // 0 = Overview, 1 = Transcript
    widget.ai.warmUp();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// One-shot "Summarize anyway" override. Deliberately not persisted: it
  /// applies to this visit only.
  bool _overrideGate = false;

  String get _transcript => (_meeting.transcript ?? '').trim();
  bool get _hasMinutes => (_meeting.minutes ?? '').isNotEmpty;

  GateVerdict get _verdict => SummarizeGate.assess(
        transcript: _transcript,
        durationMs: _meeting.durationMs,
      );

  /// Whether generation is allowed to run at all right now.
  bool get _mayGenerate => _overrideGate || _verdict.sufficient;

  void _ask() {
    final ctx = [
      if (_hasMinutes) 'Minutes:\n${_meeting.minutes}',
      'Transcript:\n$_transcript',
    ].join('\n\n');
    AskSheet.show(context, ai: widget.ai, groundingContext: ctx);
  }

  void _shareText(String body) => Share.share(body, subject: _meeting.title);

  void _snack(String m, {SnackBarAction? action}) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(m), action: action));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _rename,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(_meeting.title, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 6),
            Icon(Icons.edit_outlined,
                size: 16, color: scheme.onSurfaceVariant),
          ]),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: _onMenu,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'share_minutes', child: Text('Share minutes')),
              const PopupMenuItem(value: 'share_transcript', child: Text('Share transcript')),
              const PopupMenuItem(
                  value: 'share_items', child: Text('Share action items')),
              const PopupMenuItem(value: 'copy_all', child: Text('Copy all')),
              const PopupMenuItem(
                  value: 'export', enabled: false, child: Text('Export (coming soon)')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Overview'), Tab(text: 'Transcript')],
        ),
      ),
      body: ListenableBuilder(
        listenable: _manager,
        builder: (context, _) => Column(
          children: [
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _overviewTab(),
                  _transcriptTab(scheme),
                ],
              ),
            ),
            _AskBar(enabled: _manager.llmReady && !_busy, onTap: _ask),
          ],
        ),
      ),
    );
  }

  Future<void> _rename() async {
    // The dialog owns its TextEditingController (see _RenameDialog) so it is
    // disposed exactly when the dialog's widget is actually removed from the
    // tree — i.e. after the pop/exit animation finishes. Disposing a
    // controller manually right after `await showDialog` returns is too
    // early: the dialog is still rendering its closing transition and would
    // hit "TextEditingController used after being disposed".
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initialTitle: _meeting.title),
    );
    final name = result?.trim();
    if (name == null || name.isEmpty) return;
    setState(() => _meeting = _meeting.copyWith(title: name));
    await widget.repository.update(_meeting);
  }

  void _onMenu(String value) {
    switch (value) {
      case 'share_minutes':
        if (_hasMinutes) {
          _shareText(_meeting.minutes!);
        } else {
          _snack('No minutes yet.');
        }
      case 'share_transcript':
        _shareText(_transcript);
      case 'share_items':
        final text = actionItemsAsText(_meeting.actionItems);
        if (text.isEmpty) {
          _snack('No action items yet.');
        } else {
          _shareText(text);
        }
      case 'copy_all':
        Clipboard.setData(ClipboardData(text: copyAllText(_meeting)));
        _snack('Copied to clipboard');
    }
  }

  Widget _transcriptTab(ColorScheme scheme) {
    if (_transcript.isEmpty) {
      return Center(
        child: Text('No transcript.',
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        SelectableText(_transcript,
            style: const TextStyle(fontSize: 16, height: 1.55)),
      ],
    );
  }

  Future<void> _generateOverview() async {
    if (_busy || _transcript.isEmpty) return;
    if (!_mayGenerate) return;
    setState(() {
      _busy = true;
      _genFailed = false;
      _busyLabel = 'Generating minutes…';
      _progress = 0;
      _streaming = '';
    });

    try {
      // 1) Minutes (streamed).
      final minutes = await widget.ai.summarize(
        _transcript,
        onToken: (partial) {
          if (mounted) setState(() => _streaming = partial);
        },
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      if (minutes == null) {
        _snack('AI model not installed yet.');
        setState(() => _busy = false);
        return;
      }
      _meeting = _meeting.copyWith(minutes: minutes);
      await widget.repository.update(_meeting);

      // 2) Action items from the minutes.
      final items = await widget.ai.actionItems(minutes);
      if (!mounted) return;
      if (items != null) {
        _meeting = _meeting.copyWith(
            actionItems: items.map((t) => ActionItem(text: t)).toList());
        await widget.repository.update(_meeting);
      }

      // 3) Title — only if still the default placeholder.
      if (isDefaultMeetingTitle(_meeting.title)) {
        final title = await widget.ai.generateTitle(_transcript);
        if (mounted && title != null && title.isNotEmpty) {
          _meeting = _meeting.copyWith(title: title);
          await widget.repository.update(_meeting);
        }
      }

      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _genFailed = true;
          _busyLabel = 'Couldn’t generate minutes';
        });
        _snack('Generation failed. Tap Regenerate to retry.');
      }
    }
  }

  Future<void> _summarizeAnyway() async {
    setState(() => _overrideGate = true);
    await _generateOverview();
  }

  /// Kick the pass once, when the model is ready and nothing is cached yet.
  void _maybeAutoGenerate() {
    if (_autoStarted) return;
    if (_hasMinutes || _meeting.actionItems.isNotEmpty) return;
    if (_transcript.isEmpty || !_manager.llmReady) return;
    if (!_mayGenerate) return;
    _autoStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _generateOverview());
  }

  Widget _overviewTab() {
    _maybeAutoGenerate();
    return OverviewTab(
      meeting: _meeting,
      verdict: _verdict,
      busy: _busy,
      genFailed: _genFailed,
      busyLabel: _busyLabel,
      progress: _progress,
      streaming: _streaming,
      preparing: _transcript.isNotEmpty && !_manager.llmReady,
      overridden: _overrideGate,
      onGenerate: _generateOverview,
      onRegenerate: _regenerate,
      onToggleItem: _toggleItem,
      onSummarizeAnyway: _summarizeAnyway,
      onEditMinutes: _editMinutes,
    );
  }

  Future<void> _editMinutes() async {
    final edited = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            MinutesEditorScreen(initialText: _meeting.minutes ?? ''),
      ),
    );
    if (edited == null || !mounted) return;
    setState(() {
      _meeting = _meeting.copyWith(
        minutes: edited,
        minutesEditedAt: DateTime.now(),
      );
    });
    await widget.repository.update(_meeting);
  }

  Future<void> _regenerate() async {
    // Check the gate *before* clearing: a blocked regenerate must leave
    // existing minutes intact rather than wiping them and putting nothing back.
    if (!_mayGenerate) {
      // The blocked empty-state (OverviewTab) only renders when there are no
      // minutes and no action items yet. A meeting summarized before the
      // gate existed has minutes already, so that state never shows here —
      // without this SnackBar, tapping Regenerate would do nothing visible
      // at all. Same reason copy, same escape hatch as the blocked state.
      _snack(
        gateBlockedReason(_verdict, _meeting.durationMs),
        action: SnackBarAction(
          label: 'Summarize anyway',
          onPressed: _summarizeAnyway,
        ),
      );
      setState(() {}); // Surface the blocked state; keep the minutes.
      return;
    }
    _meeting = _meeting.copyWith(minutes: '', resetMinutesEdited: true);
    await _generateOverview();
  }

  Future<void> _toggleItem(int index, bool done) async {
    final items = List<ActionItem>.of(_meeting.actionItems);
    items[index] = items[index].copyWith(done: done);
    setState(() => _meeting = _meeting.copyWith(actionItems: items));
    await widget.repository.update(_meeting);
  }
}

/// Rename dialog content. Owns its [TextEditingController] so it is disposed
/// by the framework when this widget is actually unmounted (after the
/// dialog's exit animation), not by the caller right after the route pops.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialTitle});
  final String initialTitle;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initialTitle);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename meeting'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'Meeting title'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: const Text('Save')),
      ],
    );
  }
}

class _AskBar extends StatelessWidget {
  const _AskBar({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Material(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                Icon(Icons.chat_bubble_outline_rounded,
                    size: 20, color: scheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Text('Ask about this meeting…',
                    style: TextStyle(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
