# R4 — Home Screen Reimagining Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reimagine Home as a library-first screen — a dense, grouped meeting list (Today / This week / Earlier) with status dots — plus a persistent bottom record dock (waveform + docked mic button) that replaces the FAB, integrating the R3 STT-readiness gating.

**Architecture:** A pure, unit-tested grouping/formatting library (`home_meeting_groups.dart`) feeds a rewritten `HomeScreen`. `HomeScreen` keeps its exact constructor so `AppBootstrap` and existing tests need no wiring changes; the widget tree changes (no `AppBar`/FAB → header row + always-visible search + grouped list + bottom `_RecordDock`).

**Tech Stack:** Flutter, Material 3, existing R1 theme tokens (`Theme.of(context).colorScheme`). No new dependencies.

## Global Constraints

- **Preserve `HomeScreen`'s public constructor exactly:** `HomeScreen({super.key, required MeetingRepository repository, required AiService ai, required ValueNotifier<ThemeMode> themeMode, ModelManager? modelManager})`. `_manager = modelManager ?? ModelManager.instance`.
- **Preserve behavior:** search filter (title/transcript contains, case-insensitive), swipe-to-delete + undo, pull-to-refresh, open→`TranscriptScreen(modelManager: _manager)`, record→`RecordScreen`, R3 gating (`_record` snackbar when `!sttReady`), the R3 `_DownloadBanner` (shown when `!_manager.allReady`), settings navigation.
- **Privacy invariant:** no new network calls; the zero-network privacy gate must stay green.
- **No indefinite animations.** Status dots are static and progress indicators are determinate (driven by fraction) — repeating tickers hang `pumpAndSettle()` (learned in R3/R5). Row entrance uses one-shot `TweenAnimationBuilder` only.
- **Theme tokens only**, no hard-coded colors except the status amber `Color(0xFFEF9F27)` (no scheme token for it) and the waveform tint (`scheme.primary` with alpha).
- **`MeetingStatus`** = `{ recorded, transcribing, done, failed }`, default `recorded`.
- **Commands (prefix build/test/analyze):**
  ```bash
  export PATH="/opt/homebrew/bin:$HOME/.pub-cache/bin:/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH"
  export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
  export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
  ```
  Mobile tests: from `apps/mobile`, `flutter test`. Whole-repo analyze: `melos run analyze`.

---

## File Structure

- **Create** `apps/mobile/lib/home_meeting_groups.dart` — pure helpers: `MeetingGroup`, `groupMeetings`, `relativeLabel`, `formatDuration`, `metaLine`.
- **Create** `apps/mobile/test/home_meeting_groups_test.dart` — unit tests for the above.
- **Rewrite** `apps/mobile/lib/screens/home_screen.dart` — new layout; same constructor + behavior.
- **Update** `apps/mobile/test/screens/home_screen_test.dart` — finders for the new tree (no FAB / no search-toggle / new empty copy).

`privacy_gate_test.dart` opens a meeting by tapping its title (`Product sync`) and taps `Summarize` — the title is still a tappable row, so it needs no change; Task 3 confirms it stays green.

---

## Task 1: Pure grouping + formatting helpers

**Files:**
- Create: `apps/mobile/lib/home_meeting_groups.dart`
- Test: `apps/mobile/test/home_meeting_groups_test.dart`

**Interfaces:**
- Consumes: `Meeting`, `MeetingStatus` from `package:privoice_core/privoice_core.dart`.
- Produces:
  - `class MeetingGroup { const MeetingGroup(this.label, this.meetings); final String label; final List<Meeting> meetings; }`
  - `List<MeetingGroup> groupMeetings(List<Meeting> meetings, DateTime now)`
  - `String relativeLabel(DateTime createdAt, DateTime now)`
  - `String formatDuration(int ms)`
  - `String metaLine(Meeting m, DateTime now)`

- [ ] **Step 1: Write the failing tests**

Create `apps/mobile/test/home_meeting_groups_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/home_meeting_groups.dart';
import 'package:privoice_core/privoice_core.dart';

Meeting _m(DateTime at, {int ms = 60000, MeetingStatus status = MeetingStatus.done, String? minutes, List<String> actions = const []}) =>
    Meeting(title: 't', createdAt: at, audioPath: '', durationMs: ms, status: status, minutes: minutes, actionItems: actions);

void main() {
  final now = DateTime(2026, 7, 11, 10, 0);

  group('groupMeetings', () {
    test('buckets into Today / This week / Earlier, newest first, empties omitted', () {
      final today = _m(DateTime(2026, 7, 11, 8));
      final week = _m(DateTime(2026, 7, 8, 9)); // 3 days ago
      final earlier = _m(DateTime(2026, 6, 1));
      final groups = groupMeetings([week, earlier, today], now);
      expect(groups.map((g) => g.label).toList(), ['Today', 'This week', 'Earlier']);
      expect(groups[0].meetings.single.createdAt, today.createdAt);
    });

    test('boundaries: midnight today is Today; 7 days ago is This week; 8 days ago is Earlier', () {
      final midnight = _m(DateTime(2026, 7, 11)); // start of today
      final sevenDays = _m(DateTime(2026, 7, 4)); // exactly 7 days before start-of-today
      final eightDays = _m(DateTime(2026, 7, 3));
      final groups = groupMeetings([midnight, sevenDays, eightDays], now);
      expect(groups[0].label, 'Today');
      expect(groups[1].label, 'This week');
      expect(groups[1].meetings.single.createdAt, sevenDays.createdAt);
      expect(groups[2].label, 'Earlier');
    });

    test('only one bucket → only that group returned', () {
      expect(groupMeetings([_m(DateTime(2026, 1, 1))], now).map((g) => g.label).toList(), ['Earlier']);
      expect(groupMeetings([], now), isEmpty);
    });
  });

  group('relativeLabel', () {
    test('today shows minutes/hours, just now under a minute', () {
      expect(relativeLabel(DateTime(2026, 7, 11, 9, 0), now), '1h ago');
      expect(relativeLabel(DateTime(2026, 7, 11, 9, 45), now), '15m ago');
      expect(relativeLabel(DateTime(2026, 7, 11, 9, 59, 40), now), 'just now');
    });
    test('this week shows weekday, older shows day + month', () {
      expect(relativeLabel(DateTime(2026, 7, 8, 9), now), 'Wed'); // 2026-07-08 is a Wednesday
      expect(relativeLabel(DateTime(2026, 6, 1), now), '1 Jun');
    });
  });

  group('metaLine', () {
    test('done meeting lists time, duration, and available outputs', () {
      final m = _m(DateTime(2026, 7, 11, 9), ms: 132000, minutes: '# x', actions: ['a', 'b']);
      expect(metaLine(m, now), '1h ago · 2:12 · Minutes · 2 actions');
    });
    test('transcribing and failed short-circuit', () {
      expect(metaLine(_m(DateTime(2026, 7, 11, 9), status: MeetingStatus.transcribing), now), '1h ago · transcribing…');
      expect(metaLine(_m(DateTime(2026, 7, 11, 9), status: MeetingStatus.failed), now), '1h ago · failed');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/mobile && flutter test test/home_meeting_groups_test.dart`
Expected: FAIL — `home_meeting_groups.dart` does not exist.

- [ ] **Step 3: Implement the helpers**

Create `apps/mobile/lib/home_meeting_groups.dart`:
```dart
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/mobile && flutter test test/home_meeting_groups_test.dart`
Expected: PASS (all groups). If the weekday assertion fails, verify 2026-07-08's weekday and fix the test's expected string — not the implementation.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/home_meeting_groups.dart apps/mobile/test/home_meeting_groups_test.dart
git commit -m "feat(r4): pure meeting grouping + relative-time helpers for Home"
```

---

## Task 2: Rewrite HomeScreen (library-first + bottom record dock)

**Files:**
- Rewrite: `apps/mobile/lib/screens/home_screen.dart`
- Update: `apps/mobile/test/screens/home_screen_test.dart`

**Interfaces:**
- Consumes: `groupMeetings`, `metaLine` (Task 1); `ModelManager` (`sttReady`, `allReady`, `hasError`, `overallFraction`, `stateOf`, `ensureDefaultSet`); `Meeting`/`MeetingStatus`; `RecordScreen`, `TranscriptScreen`, `SettingsScreen`.
- Produces: same `HomeScreen` public API. The record button carries `key: const Key('recordButton')` for tests.

- [ ] **Step 1: Update the widget tests first (they will fail)**

Replace the body of `apps/mobile/test/screens/home_screen_test.dart` with:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/ai_service.dart';
import 'package:mobile/model_manager.dart';
import 'package:mobile/screens/home_screen.dart';
import 'package:privoice_core/privoice_core.dart';
import 'package:privoice_models/privoice_models.dart';

import '../fakes/fake_meeting_repository.dart';
import '../fakes/fake_model_downloader.dart';

Meeting _m(String title, String transcript, DateTime at) => Meeting(
      title: title,
      createdAt: at,
      audioPath: '',
      durationMs: 60000,
      transcript: transcript,
    );

void main() {
  ModelManager readyManager() => ModelManager(
        downloader: FakeModelDownloader(installed: {
          ModelCatalog.parakeetStt.id,
          ModelCatalog.llama1b.id,
        }),
      )..markAllReadyForTest();

  Widget host(MeetingRepository repo, {ModelManager? manager}) => MaterialApp(
        home: HomeScreen(
          repository: repo,
          ai: AiService(),
          themeMode: ValueNotifier(ThemeMode.system),
          modelManager: manager,
        ),
      );

  testWidgets('shows setup banner while models not ready', (tester) async {
    await tester.pumpWidget(host(FakeMeetingRepository(),
        manager: ModelManager(downloader: FakeModelDownloader())));
    await tester.pumpAndSettle();
    expect(find.textContaining('Setting up'), findsOneWidget);
  });

  testWidgets('no banner when all models ready', (tester) async {
    await tester.pumpWidget(host(FakeMeetingRepository(), manager: readyManager()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Setting up'), findsNothing);
  });

  testWidgets('tapping record while STT not ready shows a snackbar', (tester) async {
    await tester.pumpWidget(host(FakeMeetingRepository(),
        manager: ModelManager(downloader: FakeModelDownloader())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recordButton')));
    await tester.pump();
    expect(find.textContaining('Speech-to-text'), findsOneWidget);
  });

  testWidgets('empty repository shows the invitation and the record dock',
      (tester) async {
    await tester.pumpWidget(host(FakeMeetingRepository(), manager: readyManager()));
    await tester.pumpAndSettle();
    expect(find.textContaining('first meeting'), findsOneWidget);
    expect(find.byKey(const Key('recordButton')), findsOneWidget);
    expect(find.text('Tap to record'), findsOneWidget);
  });

  testWidgets('lists meetings grouped', (tester) async {
    final repo = FakeMeetingRepository([
      _m('Standup', 'daily sync', DateTime(2026, 7, 10, 9)),
      _m('Design review', 'ui discussion', DateTime(2026, 7, 10, 11)),
    ]);
    await tester.pumpWidget(host(repo, manager: readyManager()));
    await tester.pumpAndSettle();
    expect(find.text('Standup'), findsOneWidget);
    expect(find.text('Design review'), findsOneWidget);
  });

  testWidgets('search filters the list', (tester) async {
    final repo = FakeMeetingRepository([
      _m('Standup', 'daily sync', DateTime(2026, 7, 10, 9)),
      _m('Design review', 'ui discussion', DateTime(2026, 7, 10, 11)),
    ]);
    await tester.pumpWidget(host(repo, manager: readyManager()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'design');
    await tester.pumpAndSettle();
    expect(find.text('Design review'), findsOneWidget);
    expect(find.text('Standup'), findsNothing);
  });
}
```

(The gated-record test asserts only the snackbar: the `_record` early-return guarantees no navigation, so a snackbar with no route change is the observable behavior.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/mobile && flutter test test/screens/home_screen_test.dart`
Expected: FAIL — the old `HomeScreen` has no `Key('recordButton')`, no always-visible `TextField`, and the old empty copy; several finders miss.

- [ ] **Step 3: Rewrite `home_screen.dart`**

Replace the entire contents of `apps/mobile/lib/screens/home_screen.dart` with:
```dart
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
    if (_query.trim().isEmpty) return _all;
    final q = _query.toLowerCase();
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
      return _EmptyState(scheme: scheme, searching: _query.trim().isNotEmpty);
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

  static const _heights = [7.0, 14, 22, 11, 18, 9, 20, 12, 24, 10, 16, 8, 15];

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
```

- [ ] **Step 4: Run the Home tests to verify they pass**

Run: `cd apps/mobile && flutter test test/screens/home_screen_test.dart`
Expected: PASS (6 tests), no hang.

- [ ] **Step 5: Run analyze on the changed files**

Run: `cd apps/mobile && flutter analyze lib/screens/home_screen.dart lib/home_meeting_groups.dart test/screens/home_screen_test.dart`
Expected: "No issues found!" Fix any unused import / lint before continuing.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/screens/home_screen.dart apps/mobile/test/screens/home_screen_test.dart
git commit -m "feat(r4): reimagine Home — grouped library + bottom record dock"
```

---

## Task 3: Full verification + STATUS + device build

**Files:**
- Modify: `STATUS.md`

**Interfaces:** none.

- [ ] **Step 1: Whole-repo analyze**

Run:
```bash
export PATH="/opt/homebrew/bin:$HOME/.pub-cache/bin:/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH"
export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
melos run analyze
```
Expected: "No issues found!" for all 6 packages.

- [ ] **Step 2: Full mobile suite (incl. privacy gate + bootstrap + transcript)**

Run: `cd apps/mobile && flutter test`
Expected: all PASS. The privacy gate opens `Product sync` by tapping its title row and taps `Summarize` — confirm it still renders minutes with 0 HTTP clients. If any pre-existing test used a removed finder (FAB / search-toggle icon / 'No meetings yet' / 'Record' label) it must be updated to the new tree; only `home_screen_test.dart` is expected to need changes (already done in Task 2). If another test breaks, update its finders minimally to match the new Home and note it.

- [ ] **Step 3: Debug build**

Run: `cd apps/mobile && flutter build apk --debug`
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`.

- [ ] **Step 4: Update STATUS.md**

Edit `STATUS.md`:
- Redesign line: flip `R4 home ⬜` to `R4 home ✅ (code-complete; on-device pending)` with a note: "library-first Home — grouped meeting list (Today/This week/Earlier) with status dots + persistent bottom record dock (R3 gating integrated); FAB retired".
- `Now:` line: add R4.
- Bump **Last updated** to `2026-07-11`.

- [ ] **Step 5: Commit**

```bash
git add STATUS.md
git commit -m "docs(status): R4 Home reimagining done (code-complete)"
```

---

## Self-Review Notes

- **Spec coverage:** layout/header/search (Task 2 `_Header`/`_SearchField`) · grouped dense list + buckets (Task 1 `groupMeetings` + Task 2 `_GroupCard`/`_MeetingRow`) · status dot mapping incl. recorded/failed (Task 2 `_StatusDot`) · record dock + R3 gating (Task 2 `_RecordDock` + `_record`) · download banner retained · empty + no-match states · search filter · swipe-delete + undo · one-shot motion, static dots (no ticker) · tests (Task 1 unit, Task 2 widget, Task 3 regression). All covered.
- **Type consistency:** `groupMeetings`/`MeetingGroup`/`relativeLabel`/`formatDuration`/`metaLine` used identically across tasks; `HomeScreen` constructor unchanged; record button `Key('recordButton')` referenced in tests and defined in `_RecordDock`.
- **Placeholder scan:** none — every step contains complete, runnable code; no TBD/skip/scaffold.
