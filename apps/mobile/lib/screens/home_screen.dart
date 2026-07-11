import 'package:flutter/material.dart';
import 'package:privoice_core/privoice_core.dart';
import 'package:privoice_models/privoice_models.dart';

import '../ai_service.dart';
import '../home_meeting_groups.dart';
import '../model_manager.dart';
import 'record_screen.dart';
import 'settings_screen.dart';
import 'transcript_screen.dart';

/// Home: a grouped library of past meetings with a persistent bottom record
/// dock. Private by default — nothing in the cloud.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.ai,
    required this.themeMode,
    this.modelManager,
  });

  final MeetingRepository repository;
  final AiService ai;
  final ValueNotifier<ThemeMode> themeMode;
  final ModelManager? modelManager;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Meeting> _all = [];
  bool _loading = true;
  String _query = '';

  ModelManager get _manager => widget.modelManager ?? ModelManager.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await widget.repository.all();
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
    });
  }

  List<Meeting> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all
        .where((m) =>
            m.title.toLowerCase().contains(q) ||
            (m.transcript ?? '').toLowerCase().contains(q))
        .toList();
  }

  Future<void> _record() async {
    if (!_manager.sttReady) {
      final pct =
          (_manager.stateOf(ModelCatalog.parakeetStt).fraction * 100).round();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Speech-to-text is still downloading ($pct%)'),
      ));
      return;
    }
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecordScreen(repository: widget.repository),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _open(Meeting m) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TranscriptScreen(
          meeting: m,
          repository: widget.repository,
          ai: widget.ai,
          modelManager: _manager,
        ),
      ),
    );
    _load();
  }

  Future<void> _delete(Meeting m) async {
    setState(() => _all = _all.where((x) => x.id != m.id).toList());
    await widget.repository.delete(m.id!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted "${m.title}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await widget.repository.insert(m);
            _load();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _manager,
        builder: (context, _) => _buildScaffold(context),
      );

  Widget _buildScaffold(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(themeMode: widget.themeMode),
            _SearchField(onChanged: (v) => setState(() => _query = v)),
            if (!_manager.allReady)
              _DownloadBanner(
                fraction: _manager.overallFraction,
                hasError: _manager.hasError,
                onRetry: _manager.ensureDefaultSet,
              ),
            Expanded(child: _content(scheme)),
            _RecordDock(
              sttReady: _manager.sttReady,
              fraction: _manager.stateOf(ModelCatalog.parakeetStt).fraction,
              onTap: _record,
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(ColorScheme scheme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final visible = _visible;
    if (visible.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: _EmptyState(
                  scheme: scheme, searching: _query.trim().isNotEmpty),
            ),
          ],
        ),
      );
    }
    final now = DateTime.now();
    final groups = groupMeetings(visible, now);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          for (final g in groups) ...[
            _GroupLabel(label: g.label),
            _GroupCard(
              meetings: g.meetings,
              now: now,
              onTap: _open,
              onDelete: _delete,
            ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.themeMode});
  final ValueNotifier<ThemeMode> themeMode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
      child: Row(
        children: [
          Text('Privoice',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: scheme.onSurface)),
          const Spacer(),
          Icon(Icons.lock_outline, size: 16, color: scheme.primary),
          const SizedBox(width: 4),
          Text('On-device',
              style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => SettingsScreen(themeMode: themeMode)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: 'Search meetings',
          prefixIcon: const Icon(Icons.search, size: 20),
          isDense: true,
          filled: true,
          fillColor: scheme.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.outlineVariant)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.outlineVariant)),
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Text(label.toUpperCase(),
          style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant)),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.meetings,
    required this.now,
    required this.onTap,
    required this.onDelete,
  });
  final List<Meeting> meetings;
  final DateTime now;
  final void Function(Meeting) onTap;
  final void Function(Meeting) onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < meetings.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  thickness: 1,
                  indent: 44,
                  color: scheme.outlineVariant),
            Dismissible(
              key: ValueKey(meetings[i].id ?? meetings[i].hashCode),
              direction: DismissDirection.endToStart,
              background: Container(
                color: scheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: Icon(Icons.delete_outline,
                    color: scheme.onErrorContainer),
              ),
              onDismissed: (_) => onDelete(meetings[i]),
              child: _Entrance(
                index: i,
                child: _MeetingRow(
                    meeting: meetings[i],
                    now: now,
                    onTap: () => onTap(meetings[i])),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MeetingRow extends StatelessWidget {
  const _MeetingRow(
      {required this.meeting, required this.now, required this.onTap});
  final Meeting meeting;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        child: Row(
          children: [
            _StatusDot(status: meeting.status),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(meeting.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(metaLine(meeting, now),
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.outline, size: 20),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final MeetingStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      MeetingStatus.done => scheme.tertiary,
      MeetingStatus.transcribing => const Color(0xFFEF9F27),
      MeetingStatus.failed => scheme.error,
      MeetingStatus.recorded => scheme.onSurfaceVariant,
    };
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// One-shot staggered fade/slide entrance. Bounded (no repeating ticker).
class _Entrance extends StatelessWidget {
  const _Entrance({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + (index.clamp(0, 8)) * 50),
      curve: Curves.easeOut,
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 12), child: c),
      ),
      child: child,
    );
  }
}

class _RecordDock extends StatelessWidget {
  const _RecordDock(
      {required this.sttReady, required this.fraction, required this.onTap});
  final bool sttReady;
  final double fraction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 116,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 28,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(22)),
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 12,
            child: Center(child: _Waveform(color: scheme.primary)),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(sttReady ? 'Tap to record' : 'Preparing…',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface)),
                const SizedBox(height: 2),
                Text('Transcribed privately on your phone',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: InkWell(
                key: const Key('recordButton'),
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: sttReady
                        ? scheme.primary
                        : scheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.surface, width: 4),
                  ),
                  child: sttReady
                      ? Icon(Icons.mic_rounded,
                          color: scheme.onPrimary, size: 30)
                      : Padding(
                          padding: const EdgeInsets.all(18),
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              value: fraction,
                              color: scheme.primary),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Waveform extends StatelessWidget {
  const _Waveform({required this.color});
  final Color color;

  static const List<double> _heights = [
    7.0,
    14,
    22,
    11,
    18,
    9,
    20,
    12,
    24,
    10,
    16,
    8,
    15
  ];

  @override
  Widget build(BuildContext context) {
    final c = color.withValues(alpha: 0.30);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final h in _heights)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Container(
              width: 3,
              height: h,
              decoration: BoxDecoration(
                  color: c, borderRadius: BorderRadius.circular(2)),
            ),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.scheme, required this.searching});
  final ColorScheme scheme;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                searching
                    ? Icons.search_off_rounded
                    : Icons.graphic_eq_rounded,
                size: 60,
                color: scheme.primary),
            const SizedBox(height: 18),
            Text(searching ? 'No matches' : 'Record your first meeting',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (!searching)
              Text(
                'Tap the record button below. It’s transcribed and summarized '
                'right here on your phone — nothing is uploaded.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
              ),
          ],
        ),
      ),
    );
  }
}

class _DownloadBanner extends StatelessWidget {
  const _DownloadBanner({
    required this.fraction,
    required this.hasError,
    required this.onRetry,
  });
  final double fraction;
  final bool hasError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          Icon(hasError ? Icons.cloud_off_rounded : Icons.download_rounded,
              size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasError
                      ? 'Download paused'
                      : 'Setting up Privoice · ${(fraction * 100).round()}%',
                  style: TextStyle(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
                if (!hasError) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                        value: fraction, minHeight: 5),
                  ),
                ],
              ],
            ),
          ),
          if (hasError)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
