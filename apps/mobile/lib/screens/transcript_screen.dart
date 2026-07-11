import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:privoice_core/privoice_core.dart';
import 'package:share_plus/share_plus.dart';

import '../ai_service.dart';
import '../model_manager.dart';
import '../widgets/ask_sheet.dart';

/// Transcript + AI smart-actions (summarize → minutes, action items, ask).
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
  String _busyLabel = '';
  double _progress = 0;
  String _streaming = '';

  ModelManager get _manager => widget.modelManager ?? ModelManager.instance;

  @override
  void initState() {
    super.initState();
    _meeting = widget.meeting;
    _tabs = TabController(length: 2, vsync: this);
    // Pre-warm the model so the first smart action isn't cold.
    widget.ai.warmUp();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String get _transcript => (_meeting.transcript ?? '').trim();

  Future<void> _summarize({bool force = false}) async {
    if (_transcript.isEmpty || _busy) return;
    _tabs.animateTo(1);
    // Reuse: don't reprocess if we already have minutes.
    if (!force && (_meeting.minutes ?? '').isNotEmpty) return;
    setState(() {
      _busy = true;
      _busyLabel = 'Generating minutes…';
      _progress = 0;
      _streaming = '';
    });
    final minutes = await widget.ai.summarize(
      _transcript,
      onToken: (partial) => setState(() => _streaming = partial),
      onProgress: (p) => setState(() => _progress = p),
    );
    if (!mounted) return;
    if (minutes == null) {
      _snack('AI model not installed yet.');
      setState(() => _busy = false);
      return;
    }
    _meeting = _meeting.copyWith(minutes: minutes);
    await widget.repository.update(_meeting);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _actionItems() async {
    if (_transcript.isEmpty || _busy) return;
    if (_meeting.actionItems.isNotEmpty) {
      _tabs.animateTo(1);
      return; // reuse
    }
    setState(() {
      _busy = true;
      _busyLabel = 'Finding action items…';
      _progress = 0;
      _streaming = '';
    });
    _tabs.animateTo(1);
    // Prefer the already-generated minutes as the source (short + coherent);
    // avoids re-summarizing the whole transcript.
    final source = (_meeting.minutes ?? '').isNotEmpty
        ? _meeting.minutes!
        : _transcript;
    final items = await widget.ai.actionItems(source);
    if (!mounted) return;
    if (items == null) {
      _snack('AI model not installed yet.');
      setState(() => _busy = false);
      return;
    }
    _meeting = _meeting.copyWith(actionItems: items);
    await widget.repository.update(_meeting);
    if (mounted) setState(() => _busy = false);
  }

  void _ask() {
    final ctx = [
      if ((_meeting.minutes ?? '').isNotEmpty) 'Minutes:\n${_meeting.minutes}',
      'Transcript:\n$_transcript',
    ].join('\n\n');
    AskSheet.show(context, ai: widget.ai, groundingContext: ctx);
  }

  void _share() {
    final body = (_meeting.minutes ?? '').isNotEmpty
        ? _meeting.minutes!
        : _transcript;
    Share.share(body, subject: _meeting.title);
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_meeting.title),
        actions: [
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: _share,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Transcript'), Tab(text: 'Minutes')],
        ),
      ),
      body: Column(
        children: [
          ListenableBuilder(
            listenable: _manager,
            builder: (context, _) => _SmartActionBar(
              busy: _busy,
              aiReady: _manager.llmReady,
              onSummarize: _summarize,
              onActionItems: _actionItems,
              onAsk: _ask,
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _transcriptTab(scheme),
                _minutesTab(scheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _transcriptTab(ColorScheme scheme) {
    if (_transcript.isEmpty) {
      return Center(
        child: Text('No transcript.',
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        SelectableText(_transcript,
            style: const TextStyle(fontSize: 16, height: 1.55)),
      ],
    );
  }

  Widget _minutesTab(ColorScheme scheme) {
    if (_busy) {
      return _GeneratingView(
          label: _busyLabel, progress: _progress, streaming: _streaming);
    }

    final hasMinutes = (_meeting.minutes ?? '').isNotEmpty;
    final hasItems = _meeting.actionItems.isNotEmpty;

    if (!hasMinutes && !hasItems) {
      return _MinutesEmpty(onGenerate: _summarize);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
      children: [
        if (hasItems) ...[
          Row(children: [
            Icon(Icons.check_circle_outline, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Text('Action items',
                style: Theme.of(context).textTheme.titleSmall),
          ]),
          const SizedBox(height: 12),
          _ActionChips(items: _meeting.actionItems),
          const SizedBox(height: 24),
        ],
        if (hasMinutes)
          _RevealFade(
            child: MarkdownBody(
              data: _meeting.minutes!,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(p: const TextStyle(fontSize: 15.5, height: 1.5)),
            ),
          ),
        if (hasMinutes) ...[
          const SizedBox(height: 20),
          Center(
            child: TextButton.icon(
              onPressed: () => _summarize(force: true),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Regenerate minutes'),
            ),
          ),
        ],
      ],
    );
  }
}

class _SmartActionBar extends StatelessWidget {
  const _SmartActionBar({
    required this.busy,
    required this.aiReady,
    required this.onSummarize,
    required this.onActionItems,
    required this.onAsk,
  });

  final bool busy;
  final bool aiReady;
  final VoidCallback onSummarize;
  final VoidCallback onActionItems;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = aiReady && !busy;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!aiReady)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Row(children: [
                // Determinate (value: 0) so pumpAndSettle() in widget tests
                // doesn't hang waiting for an indeterminate animation to end.
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, value: 0, color: scheme.primary),
                ),
                const SizedBox(width: 8),
                Text('Preparing AI…',
                    style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ]),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _SmartButton(
                    icon: Icons.auto_awesome,
                    label: 'Summarize',
                    onTap: enabled ? onSummarize : null),
                const SizedBox(width: 8),
                _SmartButton(
                    icon: Icons.checklist_rounded,
                    label: 'Action items',
                    onTap: enabled ? onActionItems : null),
                const SizedBox(width: 8),
                _SmartButton(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Ask',
                    onTap: enabled ? onAsk : null),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmartButton extends StatelessWidget {
  const _SmartButton(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

class _GeneratingView extends StatelessWidget {
  const _GeneratingView(
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

class _MinutesEmpty extends StatelessWidget {
  const _MinutesEmpty({required this.onGenerate});
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_outlined, size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text('No minutes yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Generate a clean summary with decisions and action items — '
              'right here on your phone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onGenerate,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Generate minutes'),
            ),
          ],
        ),
      ),
    );
  }
}
