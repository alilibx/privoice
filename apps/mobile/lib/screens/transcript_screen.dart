import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:privoice_core/privoice_core.dart';
import 'package:share_plus/share_plus.dart';

import '../ai_service.dart';
import '../model_manager.dart';
import '../widgets/ask_sheet.dart';

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
      body: ListenableBuilder(
        listenable: _manager,
        builder: (context, _) => Column(
          children: [
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _overviewTab(scheme),
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

  Future<void> _generateOverview() async {
    if (_busy || _transcript.isEmpty) return;
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

  /// Kick the pass once, when the model is ready and nothing is cached yet.
  void _maybeAutoGenerate() {
    if (_autoStarted) return;
    if (_hasMinutes || _meeting.actionItems.isNotEmpty) return;
    if (_transcript.isEmpty || !_manager.llmReady) return;
    _autoStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _generateOverview());
  }

  Widget _overviewTab(ColorScheme scheme) {
    _maybeAutoGenerate();

    if (_busy) {
      return _GeneratingView(
          label: _busyLabel, progress: _progress, streaming: _streaming);
    }

    final hasItems = _meeting.actionItems.isNotEmpty;
    if (!_hasMinutes && !hasItems) {
      // Nothing cached and not generating: either the model is still
      // preparing, the first pass failed, or there is no transcript to work
      // from.
      final preparing = _transcript.isNotEmpty && !_manager.llmReady;
      if (_genFailed) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.error_outline, size: 48, color: scheme.error),
              const SizedBox(height: 16),
              Text('Couldn’t generate minutes',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _generateOverview,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            ]),
          ),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.auto_awesome_outlined, size: 48, color: scheme.primary),
            const SizedBox(height: 16),
            Text(preparing ? 'Preparing on-device AI…' : 'No summary yet',
                style: Theme.of(context).textTheme.titleMedium),
            if (preparing) ...[
              const SizedBox(height: 12),
              const SizedBox(
                width: 120,
                child: LinearProgressIndicator(minHeight: 4),
              ),
            ],
          ]),
        ),
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
        if (_hasMinutes) ...[
          const SizedBox(height: 20),
          Center(
            child: TextButton.icon(
              onPressed: _regenerate,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Regenerate'),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _regenerate() async {
    _meeting = _meeting.copyWith(minutes: '');
    await _generateOverview();
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
