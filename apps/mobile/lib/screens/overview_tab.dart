import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:privoice_ai/privoice_ai.dart';
import 'package:privoice_core/privoice_core.dart';

import '../widgets/action_item_list.dart';

/// Human-readable duration as m:ss (e.g. "0:13").
String formatMmss(int durationMs) {
  final total = (durationMs / 1000).round();
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Explains why [SummarizeGate] blocked generation, in the exact wording
/// shown to the user. This is the single source of truth for that copy:
/// [OverviewTab]'s blocked empty-state and transcript_screen.dart's blocked
/// Regenerate SnackBar both call this so the two paths can never drift apart.
String gateBlockedReason(GateVerdict v, int durationMs) {
  if (v.outcome == GateOutcome.tooSparse) {
    final mins = (durationMs / 60000).round();
    return '$mins minutes of audio but only ${v.wordCount} words '
        '— mostly silence.';
  }
  return 'Only ${v.wordCount} words in ${formatMmss(durationMs)}.';
}

/// Overview tab: AI-generated minutes + action items for a meeting.
class OverviewTab extends StatelessWidget {
  const OverviewTab({
    super.key,
    required this.meeting,
    required this.verdict,
    required this.busy,
    required this.genFailed,
    required this.busyLabel,
    required this.progress,
    required this.streaming,
    required this.preparing,
    required this.overridden,
    required this.onGenerate,
    required this.onRegenerate,
    required this.onToggleItem,
    required this.onEditItemText,
    required this.onAddItem,
    required this.onDeleteItem,
    required this.onReorderItems,
    required this.onSummarizeAnyway,
    required this.onEditMinutes,
  });

  final Meeting meeting;
  final GateVerdict verdict;
  final bool busy;
  final bool genFailed;
  final String busyLabel;
  final double progress;
  final String streaming;
  final bool preparing;
  final bool overridden;
  final Future<void> Function() onGenerate;
  final Future<void> Function() onRegenerate;
  final Future<void> Function(int index, bool done) onToggleItem;
  final Future<void> Function(int index, String text) onEditItemText;
  final Future<void> Function(String text) onAddItem;
  final Future<void> Function(int index) onDeleteItem;
  final Future<void> Function(int oldIndex, int newIndex) onReorderItems;
  final VoidCallback onSummarizeAnyway;
  final VoidCallback onEditMinutes;

  bool get _hasMinutes => (meeting.minutes ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (busy) {
      return GeneratingView(
          label: busyLabel, progress: progress, streaming: streaming);
    }

    final hasItems = meeting.actionItems.isNotEmpty;

    if (!_hasMinutes &&
        !hasItems &&
        !busy &&
        !overridden &&
        !verdict.sufficient) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          Icon(Icons.graphic_eq_rounded, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text('Not enough speech to summarize', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(gateBlockedReason(verdict, meeting.durationMs),
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          Center(
            child: TextButton(
              onPressed: onSummarizeAnyway,
              child: const Text('Summarize anyway'),
            ),
          ),
          const SizedBox(height: 24),
          Text('What was recorded', style: textTheme.titleSmall),
          const SizedBox(height: 8),
          SelectableText(meeting.transcript ?? ''),
        ],
      );
    }

    if (!_hasMinutes && !hasItems) {
      // Nothing cached and not generating: either the model is still
      // preparing, the first pass failed, or there is no transcript to work
      // from.
      if (genFailed) {
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
                onPressed: onGenerate,
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
        if (hasItems || _hasMinutes) ...[
          Row(children: [
            Icon(Icons.check_circle_outline, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Text('Action items',
                style: Theme.of(context).textTheme.titleSmall),
          ]),
          const SizedBox(height: 12),
          ActionItemList(
            items: meeting.actionItems,
            onToggle: onToggleItem,
            onEditText: onEditItemText,
            onAdd: onAddItem,
            onDelete: onDeleteItem,
            onReorder: onReorderItems,
          ),
          const SizedBox(height: 24),
        ],
        if (_hasMinutes)
          RevealFade(
            child: MarkdownBody(
              data: meeting.minutes!,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(p: const TextStyle(fontSize: 15.5, height: 1.5)),
            ),
          ),
        if (_hasMinutes) ...[
          const SizedBox(height: 20),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: onEditMinutes,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  onPressed: onRegenerate,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Regenerate'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Staggered fade/slide-in wrapper (no controller — safe under pumpAndSettle).
class AnimatedIn extends StatelessWidget {
  const AnimatedIn({super.key, required this.child, this.delayMs = 0});
  final Widget child;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + delayMs),
      curve: Curves.easeOut,
      builder: (_, t, c) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: c),
      ),
      child: child,
    );
  }
}

class RevealFade extends StatelessWidget {
  const RevealFade({super.key, required this.child});
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

class GeneratingView extends StatelessWidget {
  const GeneratingView(
      {super.key, required this.label, required this.progress, this.streaming = ''});
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
