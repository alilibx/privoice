import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:privoice_core/privoice_core.dart';
import 'package:privoice_models/privoice_models.dart';

import '../ai_service.dart';
import '../home_meeting_groups.dart';
import '../model_manager.dart';
import 'import_screen.dart';
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
    this.audioStore,
  });

  final MeetingRepository repository;
  final AiService ai;
  final ValueNotifier<ThemeMode> themeMode;
  final ModelManager? modelManager;

  /// Defaults to [MeetingAudioStore.forApp]. Injected in tests, which cannot
  /// reach `path_provider`.
  final MeetingAudioStore? audioStore;

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

  Future<void> _import() async {
    // Check the model before the picker, not after the transcode: converting a
    // 90-minute file and *then* saying "model not ready" throws away minutes of
    // the user's time, and a first-run user is exactly the one still downloading.
    if (!_manager.sttReady) {
      final pct =
          (_manager.stateOf(ModelCatalog.parakeetStt).fraction * 100).round();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Speech-to-text is still downloading ($pct%)'),
      ));
      return;
    }

    String? path;
    try {
      // file_picker 11 exposes pickFiles as a static; the older
      // `FilePicker.platform.pickFiles` accessor no longer exists.
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'm4a', 'mp3', 'wav', 'aac', 'aiff', 'caf', 'flac',
          'ogg', 'opus', 'amr', 'mp4', 'mov', 'webm',
        ],
      );
      // `.single` would throw when the platform returns an empty list, which it
      // does on Android if copying the picked file into cache failed.
      path = picked?.files.firstOrNull?.path;
    } catch (e) {
      // Tapping Import twice yields PlatformException('already_active'), and a
      // failed URI resolution throws too. Unhandled, both are silent no-ops.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open the file picker.")),
        );
      }
      return;
    }
    if (path == null || !mounted) return; // cancelled
    // A mutable local captured by the route builder below is not promoted; bind
    // the non-null value to a final so the closure sees a String, not a String?.
    final source = path;

    try {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ImportScreen(
            repository: widget.repository,
            sourcePath: source,
          ),
        ),
      );
      if (saved == true) _load(); // same refresh the record flow triggers
    } finally {
      // The picker handed us a full-size *copy* in cache (Android
      // <cacheDir>/file_picker/<millis>/, iOS NSTemporaryDirectory) — a 1.5 GB
      // Zoom .mp4 costs 1.5 GB there, and re-importing copies it again. Only
      // safe once the import is done reading it.
      await FilePicker.clearTemporaryFiles();
    }
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

    // Undo's re-insert is async and can outlive the dismiss animation, so hold
    // its future — collecting before it lands would delete the file the user
    // just restored.
    Future<void>? undo;
    final closed = ScaffoldMessenger.of(context)
        .showSnackBar(
          SnackBar(
            content: Text('Deleted "${m.title}"'),
            // A SnackBar with an action defaults `persist` to true
            // (`snack_bar.dart`: `persist = persist ?? action != null`), and
            // `ScaffoldMessengerState.build` makes the auto-dismiss timer
            // `return` without hiding when persist is set — so this SnackBar
            // would stay on screen indefinitely and the Undo window would
            // never close, which is the moment reclamation runs. Hence
            // `persist: false`.
            //
            // The cost, deliberately accepted: `persist` is also how Flutter
            // now implements the "a SnackBar with an action does not time out
            // under TalkBack/VoiceOver" exemption (still documented on
            // `SnackBar` itself). Opting out of persist opts out of that too,
            // so a screen-reader user gets a bounded — and unanimated, since
            // accessibleNavigation makes the dismiss instant — window to
            // double-tap Undo on a destructive action. 10s rather than the 4s
            // default is the concession: long enough to hear the announcement
            // and act, still short enough that the file is reclaimed promptly.
            persist: false,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => undo = _undoDelete(m),
            ),
          ),
        )
        .closed;

    await closed;
    await undo;
    // Deliberately not branching on the close reason. Once the SnackBar is gone
    // the only question that matters is whether any row still references the
    // file; if Undo ran, it does, and the file is kept. That stays correct if
    // Undo ever becomes reachable another way.
    await _collectAudio(m.audioPath);
  }

  Future<void> _undoDelete(Meeting m) async {
    await widget.repository.insert(m);
    await _load();
  }

  /// Reclaims [audioPath] if no meeting still references it.
  ///
  /// Targeted at the one file whose row was just deleted, **not** a sweep. This
  /// runs when the Undo SnackBar closes, and that moment is not quiescent:
  /// `ScaffoldMessenger` lives above the `Navigator`, so the timer arms and
  /// this continuation resumes while this state is still mounted, no matter
  /// which route is on top. A sweep here would delete a recording started
  /// during the window (its WAV exists before its row does) and the audio of a
  /// second delete whose own Undo is still on screen. Naming one file makes
  /// both impossible — they are different names.
  ///
  /// Failing to reclaim disk must never surface over a successful delete — the
  /// startup pass retries.
  Future<void> _collectAudio(String audioPath) async {
    try {
      final store = widget.audioStore ?? await MeetingAudioStore.forApp();
      await store.collectOne(audioPath, await widget.repository.audioPaths());
    } catch (e) {
      // Swallowed, but not silently — a bare `catch (_) {}` here would hide a
      // real bug forever, and this path is invisible to the user by design.
      debugPrint('Audio collection after delete skipped: $e');
    }
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
            _Header(themeMode: widget.themeMode, onImport: _import),
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
  const _Header({required this.themeMode, required this.onImport});
  final ValueNotifier<ThemeMode> themeMode;
  final VoidCallback onImport;

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
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Import',
            onPressed: onImport,
          ),
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
