import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:privoice_core/privoice_core.dart';
import 'package:share_plus/share_plus.dart';

import '../ai_service.dart';
import '../model_manager.dart';
import '../widgets/ask_sheet.dart';

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

  // Never set true in Task 4 (no generation pass yet); Task 5 drives this via
  // setState during auto-generate and reintroduces the progress/streaming
  // state alongside it.
  // ignore: prefer_final_fields
  bool _busy = false;

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

  String get _transcript => (_meeting.transcript ?? '').trim();
  bool get _hasMinutes => (_meeting.minutes ?? '').isNotEmpty;

  void _ask() {
    final ctx = [
      if (_hasMinutes) 'Minutes:\n${_meeting.minutes}',
      'Transcript:\n$_transcript',
    ].join('\n\n');
    AskSheet.show(context, ai: widget.ai, groundingContext: ctx);
  }

  void _shareText(String body) => Share.share(body, subject: _meeting.title);

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_meeting.title),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: _onMenu,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'share_minutes', child: Text('Share minutes')),
              const PopupMenuItem(value: 'share_transcript', child: Text('Share transcript')),
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
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: _manager,
              builder: (context, _) => TabBarView(
                controller: _tabs,
                children: [
                  _overviewTab(scheme),
                  _transcriptTab(scheme),
                ],
              ),
            ),
          ),
          _AskBar(enabled: _manager.llmReady && !_busy, onTap: _ask),
        ],
      ),
    );
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
      case 'copy_all':
        // Real assembly lands in Task 8; for now share minutes-or-transcript.
        _shareText(_hasMinutes ? _meeting.minutes! : _transcript);
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

  Widget _overviewTab(ColorScheme scheme) {
    final hasItems = _meeting.actionItems.isNotEmpty;
    if (!_hasMinutes && !hasItems) {
      // Auto-generate arrives in Task 5; until then show a calm placeholder.
      return Center(
        child: Text('No summary yet.',
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        if (hasItems) ...[
          Row(children: [
            Icon(Icons.check_circle_outline, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Text('Action items',
                style: Theme.of(context).textTheme.titleSmall),
          ]),
          const SizedBox(height: 12),
          _ActionChips(items: _meeting.actionItems.map((a) => a.text).toList()),
          const SizedBox(height: 24),
        ],
        if (_hasMinutes)
          _RevealFade(
            child: MarkdownBody(
              data: _meeting.minutes!,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(p: const TextStyle(fontSize: 15.5, height: 1.5)),
            ),
          ),
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

/// Staggered scale/fade-in chips.
class _ActionChips extends StatelessWidget {
  const _ActionChips({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < items.length; i++)
          TweenAnimationBuilder<double>(
            // Index-prefixed: the LLM can emit identical action items, and a
            // bare ValueKey(text) would collide (duplicate-key crash).
            key: ValueKey('$i:${items[i]}'),
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 260 + i * 70),
            curve: Curves.easeOutBack,
            builder: (_, t, child) => Opacity(
              opacity: t.clamp(0, 1),
              child: Transform.scale(scale: 0.8 + 0.2 * t, child: child),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.task_alt,
                      size: 15, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.7),
                    child: Text(items[i],
                        style: TextStyle(color: scheme.onPrimaryContainer)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RevealFade extends StatelessWidget {
  const _RevealFade({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 12), child: c),
      ),
      child: child,
    );
  }
}

// Reused starting Task 5 (auto-generate pass shows this while busy).
// ignore: unused_element
class _GeneratingView extends StatelessWidget {
  const _GeneratingView(
      // ignore: unused_element_parameter
      {required this.label, required this.progress, this.streaming = ''});
  final String label;
  final double progress;
  final String streaming;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Once tokens start streaming, show the text appearing live (feels instant).
    if (streaming.trim().isNotEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
        children: [
          Row(children: [
            _PulsingSparkle(color: scheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 16),
          Text(streaming, style: const TextStyle(fontSize: 15.5, height: 1.5)),
        ],
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingSparkle(color: scheme.primary),
          const SizedBox(height: 20),
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          SizedBox(
            width: 200,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('On-device · nothing leaves your phone',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }
}

class _PulsingSparkle extends StatefulWidget {
  const _PulsingSparkle({required this.color, this.size = 44});
  final Color color;
  final double size;
  @override
  State<_PulsingSparkle> createState() => _PulsingSparkleState();
}

class _PulsingSparkleState extends State<_PulsingSparkle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 0.85, end: 1.15)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Icon(Icons.auto_awesome, size: widget.size, color: widget.color),
    );
  }
}
