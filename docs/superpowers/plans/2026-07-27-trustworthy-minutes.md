# Trustworthy Minutes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the app fabricating minutes from near-empty recordings, and let the user edit the minutes and action items it does produce.

**Architecture:** A pure-Dart `SummarizeGate` in `packages/ai` decides whether a transcript is substantial enough to summarize; both generation entry points consult it before any LLM call. `packages/core` gains one nullable column (`minutes_edited_at`, schema v4) to drive a Regenerate confirmation. The 632-line `transcript_screen.dart` is split so the Overview tab, the minutes editor, and the action-item list are separately testable widgets.

**Tech Stack:** Flutter 3.44.5 / Dart 3.12.2, Melos monorepo, sqflite, flutter_markdown, `flutter_test`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-27-trustworthy-minutes-design.md`. Read it before Task 1.
- Thresholds, exact values: `minWords = 30`, `minWordsPerMinute = 20`, `densityFloorMs = 60_000`.
- `packages/ai` must not import Flutter. `SummarizeGate` is pure Dart so it tests without a widget harness.
- The gate governs **generation, not display**. Minutes that already exist are never hidden or deleted.
- Blocked state is **derived at render time**. Do not add a `MeetingStatus` value and do not persist it.
- Every task ends green: `melos run analyze` clean and `melos run test` passing. The 104 pre-existing tests must stay green — and must stay *meaningful* (see Task 3).
- Conventional Commits. Work on branch `feat/trustworthy-minutes` (already created).
- Run commands with the repo's env: `export PATH="/opt/homebrew/bin:$HOME/.pub-cache/bin:$PATH"`.
- User-facing copy is fixed by this plan. Use the exact strings given; do not paraphrase.

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `packages/ai/lib/src/summarize_gate.dart` | Create | Pure sufficiency rules + verdict type |
| `packages/ai/lib/privoice_ai.dart` | Modify | Export the gate |
| `packages/ai/test/summarize_gate_test.dart` | Create | Threshold and boundary unit tests |
| `packages/core/lib/src/meeting.dart` | Modify | `minutesEditedAt` field, row mapping, copyWith |
| `packages/core/lib/src/meeting_repository.dart` | Modify | Schema v4 + migration |
| `packages/core/test/meeting_test.dart` | Modify | Round-trip incl. null |
| `packages/core/test/meeting_repository_test.dart` | Modify | v3→v4 migration preserves rows |
| `apps/mobile/lib/screens/transcript_screen.dart` | Modify | Shrinks: scaffold, tabs, rename, share, orchestration |
| `apps/mobile/lib/screens/overview_tab.dart` | Create | Minutes + items + blocked state + Regenerate |
| `apps/mobile/lib/screens/minutes_editor_screen.dart` | Create | Full-screen Markdown editor |
| `apps/mobile/lib/widgets/action_item_list.dart` | Create | Checkable, editable, reorderable list |
| `apps/mobile/lib/screens/home_screen.dart` | Modify | "Transcript only" subtitle |
| `apps/mobile/test/screens/transcript_screen_test.dart` | Modify | Fixture migration + gate/editor/regenerate tests |
| `apps/mobile/test/privacy_gate_test.dart` | Modify | Fixture migration (keeps the assertion meaningful) |
| `apps/mobile/test/screens/minutes_editor_test.dart` | Create | Editor save/cancel |
| `apps/mobile/test/widgets/action_item_list_test.dart` | Create | Add/edit/delete/reorder |
| `STATUS.md` | Modify | Mark the slice done |

---

### Task 1: `SummarizeGate`

**Files:**
- Create: `packages/ai/lib/src/summarize_gate.dart`
- Modify: `packages/ai/lib/privoice_ai.dart`
- Test: `packages/ai/test/summarize_gate_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum GateOutcome { sufficient, tooFewWords, tooSparse }`; `class GateVerdict` with `GateOutcome outcome`, `int wordCount`, `double wordsPerMinute`, `bool get sufficient`; `class SummarizeGate` with `static const int minWords`, `static const int minWordsPerMinute`, `static const int densityFloorMs`, and `static GateVerdict assess({required String transcript, required int durationMs})`.

- [ ] **Step 1: Write the failing test**

Create `packages/ai/test/summarize_gate_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_ai/privoice_ai.dart';

/// Builds a transcript with exactly [n] whitespace-separated words.
String _words(int n) => List.generate(n, (i) => 'word$i').join(' ');

void main() {
  group('SummarizeGate.assess', () {
    test('empty transcript is tooFewWords', () {
      final v = SummarizeGate.assess(transcript: '', durationMs: 60000);
      expect(v.outcome, GateOutcome.tooFewWords);
      expect(v.sufficient, isFalse);
      expect(v.wordCount, 0);
    });

    test('whitespace-only transcript is tooFewWords', () {
      final v =
          SummarizeGate.assess(transcript: '   \n\t  ', durationMs: 60000);
      expect(v.outcome, GateOutcome.tooFewWords);
      expect(v.wordCount, 0);
    });

    // The real regression: the iOS bring-up recorded 13s that transcribed to
    // "So is it working?" and the app invented a full meeting from it.
    test('the "So is it working?" case is tooFewWords', () {
      final v = SummarizeGate.assess(
          transcript: 'So is it working?', durationMs: 13000);
      expect(v.outcome, GateOutcome.tooFewWords);
      expect(v.wordCount, 4);
    });

    test('29 words is blocked, 30 and 31 are sufficient', () {
      expect(SummarizeGate.assess(transcript: _words(29), durationMs: 30000)
          .outcome, GateOutcome.tooFewWords);
      expect(SummarizeGate.assess(transcript: _words(30), durationMs: 30000)
          .outcome, GateOutcome.sufficient);
      expect(SummarizeGate.assess(transcript: _words(31), durationMs: 30000)
          .outcome, GateOutcome.sufficient);
    });

    test('40 words over 18 minutes is tooSparse', () {
      final v = SummarizeGate.assess(
          transcript: _words(40), durationMs: 18 * 60 * 1000);
      expect(v.outcome, GateOutcome.tooSparse);
      expect(v.wordsPerMinute, closeTo(2.22, 0.01));
    });

    test('40 words over 15 seconds is sufficient (below the density floor)',
        () {
      final v =
          SummarizeGate.assess(transcript: _words(40), durationMs: 15000);
      expect(v.outcome, GateOutcome.sufficient);
    });

    test('at the density floor exactly, the rate rule applies', () {
      // 30 words in 60s = 30 wpm, clears the 20 wpm bar.
      expect(
          SummarizeGate.assess(
                  transcript: _words(30), durationMs: SummarizeGate.densityFloorMs)
              .outcome,
          GateOutcome.sufficient);
      // The word rule is checked first, so 10 words is tooFewWords, not tooSparse.
      expect(
          SummarizeGate.assess(
                  transcript: _words(10), durationMs: SummarizeGate.densityFloorMs)
              .outcome,
          GateOutcome.tooFewWords);
    });

    test('durationMs of 0 skips the density rule instead of dividing by zero',
        () {
      final v = SummarizeGate.assess(transcript: _words(30), durationMs: 0);
      expect(v.outcome, GateOutcome.sufficient);
      expect(v.wordsPerMinute, 0);
    });

    test('negative durationMs is treated like zero', () {
      final v = SummarizeGate.assess(transcript: _words(30), durationMs: -5);
      expect(v.outcome, GateOutcome.sufficient);
    });

    test('reports wordCount and wordsPerMinute for UI copy', () {
      final v =
          SummarizeGate.assess(transcript: _words(120), durationMs: 120000);
      expect(v.wordCount, 120);
      expect(v.wordsPerMinute, closeTo(60, 0.01));
    });

    test('collapses irregular whitespace when counting', () {
      final v = SummarizeGate.assess(
          transcript: 'one   two\n\nthree\tfour  ', durationMs: 0);
      expect(v.wordCount, 4);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/ai && flutter test test/summarize_gate_test.dart`
Expected: FAIL — compile error, `SummarizeGate` / `GateOutcome` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `packages/ai/lib/src/summarize_gate.dart`:

```dart
/// Why a transcript was judged unsuitable for summarizing.
enum GateOutcome {
  /// Substantial enough to summarize.
  sufficient,

  /// Fewer than [SummarizeGate.minWords] words in total.
  tooFewWords,

  /// Long recording, very little speech — mostly silence.
  tooSparse,
}

/// The gate's answer, carrying the numbers the UI quotes back to the user.
class GateVerdict {
  const GateVerdict({
    required this.outcome,
    required this.wordCount,
    required this.wordsPerMinute,
  });

  final GateOutcome outcome;
  final int wordCount;

  /// Speech rate, or 0 when the duration is unknown/non-positive.
  final double wordsPerMinute;

  bool get sufficient => outcome == GateOutcome.sufficient;
}

/// Decides whether a transcript has enough substance to summarize.
///
/// Exists because an LLM asked to summarize four words will not decline — it
/// invents a plausible meeting. A 13-second recording that transcribed to
/// "So is it working?" produced minutes with three key points, a decision to
/// proceed to deployment, and four action items, none of which happened.
/// Refusing is the honest answer, so the decision is made here, before any
/// inference runs.
class SummarizeGate {
  /// Below this many words, there is nothing to summarize.
  static const int minWords = 30;

  /// Below this rate, a recording is mostly silence.
  static const int minWordsPerMinute = 20;

  /// The rate rule only applies to recordings at least this long, so a short,
  /// deliberately dense voice note is judged on word count alone.
  static const int densityFloorMs = 60000;

  static GateVerdict assess({
    required String transcript,
    required int durationMs,
  }) {
    final words = transcript.split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    final minutes = durationMs > 0 ? durationMs / 60000 : 0.0;
    final wpm = minutes > 0 ? words / minutes : 0.0;

    if (words < minWords) {
      return GateVerdict(
        outcome: GateOutcome.tooFewWords,
        wordCount: words,
        wordsPerMinute: wpm,
      );
    }
    if (durationMs >= densityFloorMs && wpm < minWordsPerMinute) {
      return GateVerdict(
        outcome: GateOutcome.tooSparse,
        wordCount: words,
        wordsPerMinute: wpm,
      );
    }
    return GateVerdict(
      outcome: GateOutcome.sufficient,
      wordCount: words,
      wordsPerMinute: wpm,
    );
  }
}
```

Add the export to `packages/ai/lib/privoice_ai.dart`, keeping the list alphabetical:

```dart
export 'src/prompts.dart';
export 'src/summarize_gate.dart';
export 'src/title.dart';
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/ai && flutter test test/summarize_gate_test.dart`
Expected: PASS, 11 tests.

Then run the whole suite and the analyzer:
Run: `melos run analyze && melos run test`
Expected: clean, all green.

- [ ] **Step 5: Commit**

```bash
git add packages/ai/lib/src/summarize_gate.dart packages/ai/lib/privoice_ai.dart packages/ai/test/summarize_gate_test.dart
git commit -m "feat(ai): SummarizeGate — refuse to summarize near-empty transcripts"
```

---

### Task 2: `Meeting.minutesEditedAt` + schema v4

**Files:**
- Modify: `packages/core/lib/src/meeting.dart`
- Modify: `packages/core/lib/src/meeting_repository.dart:28` (`schemaVersion`) and `:46-...` (`onUpgrade`), `:30-44` (`onCreate`)
- Test: `packages/core/test/meeting_test.dart`, `packages/core/test/meeting_repository_test.dart`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `Meeting.minutesEditedAt` (`DateTime?`); `Meeting.copyWith({..., DateTime? minutesEditedAt, bool resetMinutesEdited = false})`; `SqfliteMeetingRepository.schemaVersion == 4`; column `minutes_edited_at INTEGER` (epoch ms, nullable).

**Why `resetMinutesEdited`:** `copyWith` uses `?? this.x` throughout, so a null argument means "unchanged" and cannot clear a field. Regenerate must clear the edited stamp (freshly generated minutes are not hand-edited), so it needs an explicit flag rather than a null.

- [ ] **Step 1: Write the failing tests**

Append to `packages/core/test/meeting_test.dart` (inside the existing `main()`):

```dart
  group('minutesEditedAt', () {
    Meeting base() => Meeting(
          id: 1,
          title: 'Product sync',
          createdAt: DateTime(2026, 7, 27, 9, 30),
          audioPath: '/tmp/a.wav',
          durationMs: 60000,
          transcript: 'hello',
        );

    test('defaults to null and round-trips as null', () {
      final m = base();
      expect(m.minutesEditedAt, isNull);
      expect(m.toRow()['minutes_edited_at'], isNull);
      expect(Meeting.fromRow(m.toRow()).minutesEditedAt, isNull);
    });

    test('round-trips a timestamp through toRow/fromRow', () {
      final stamp = DateTime(2026, 7, 27, 10, 15);
      final m = base().copyWith(minutesEditedAt: stamp);
      expect(m.toRow()['minutes_edited_at'], stamp.millisecondsSinceEpoch);
      expect(Meeting.fromRow(m.toRow()).minutesEditedAt, stamp);
    });

    test('copyWith without the arg preserves an existing stamp', () {
      final stamp = DateTime(2026, 7, 27, 10, 15);
      final m = base().copyWith(minutesEditedAt: stamp);
      expect(m.copyWith(title: 'Renamed').minutesEditedAt, stamp);
    });

    test('resetMinutesEdited clears the stamp', () {
      final m = base().copyWith(minutesEditedAt: DateTime(2026, 7, 27));
      expect(m.copyWith(resetMinutesEdited: true).minutesEditedAt, isNull);
    });
  });
```

Append to `packages/core/test/meeting_repository_test.dart` (inside the existing `main()`; it already opens in-memory ffi databases — follow the file's existing setup helper):

```dart
  test('v3 -> v4 migration adds minutes_edited_at and preserves rows', () async {
    // Build a v3 database by hand: the pre-v4 schema, with a row in it.
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE meetings (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              audio_path TEXT NOT NULL,
              duration_ms INTEGER NOT NULL,
              transcript TEXT,
              minutes TEXT,
              action_items TEXT,
              status TEXT NOT NULL
            )
          ''');
          await db.insert('meetings', {
            'title': 'Legacy meeting',
            'created_at': DateTime(2026, 7, 1).millisecondsSinceEpoch,
            'audio_path': '/tmp/legacy.wav',
            'duration_ms': 120000,
            'transcript': 'legacy transcript',
            'minutes': '### Summary\nLegacy.',
            'action_items': '[{"text":"do it","done":true}]',
            'status': 'done',
          });
        },
      ),
    );
    await db.close();

    // Reopen at the current version so onUpgrade runs.
    final upgraded = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: SqfliteMeetingRepository.schemaVersion,
        onCreate: SqfliteMeetingRepository.onCreate,
        onUpgrade: SqfliteMeetingRepository.onUpgrade,
      ),
    );
    final repo = SqfliteMeetingRepository.fromDatabase(upgraded);
    final all = await repo.all();

    expect(all, hasLength(1));
    expect(all.first.title, 'Legacy meeting');
    expect(all.first.minutes, '### Summary\nLegacy.');
    expect(all.first.actionItems.single.text, 'do it');
    expect(all.first.actionItems.single.done, isTrue);
    // The new column exists and is null for pre-v4 rows.
    expect(all.first.minutesEditedAt, isNull);
    await upgraded.close();
  });
```

> Note: `inMemoryDatabasePath` gives a fresh database per open, so if the file's existing tests use a shared path helper, reuse that helper here instead so the reopen hits the *same* database. Check the file's existing setup before writing this test and match it.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/core && flutter test`
Expected: FAIL — `minutesEditedAt` and `resetMinutesEdited` are not defined.

- [ ] **Step 3: Write minimal implementation**

In `packages/core/lib/src/meeting.dart`, add the constructor param, field, `copyWith` handling, and row mapping:

```dart
  const Meeting({
    this.id,
    required this.title,
    required this.createdAt,
    required this.audioPath,
    required this.durationMs,
    this.transcript,
    this.minutes,
    this.actionItems = const [],
    this.status = MeetingStatus.recorded,
    this.minutesEditedAt,
  });
```

```dart
  /// When the user last hand-edited [minutes], or null if the text is exactly
  /// what the model produced. Drives the "Regenerate replaces your edits"
  /// confirmation.
  final DateTime? minutesEditedAt;
```

```dart
  Meeting copyWith({
    int? id,
    String? title,
    String? transcript,
    String? minutes,
    List<ActionItem>? actionItems,
    MeetingStatus? status,
    DateTime? minutesEditedAt,
    // copyWith treats null as "unchanged", so clearing needs an explicit flag.
    bool resetMinutesEdited = false,
  }) {
    return Meeting(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt,
      audioPath: audioPath,
      durationMs: durationMs,
      transcript: transcript ?? this.transcript,
      minutes: minutes ?? this.minutes,
      actionItems: actionItems ?? this.actionItems,
      status: status ?? this.status,
      minutesEditedAt: resetMinutesEdited
          ? null
          : (minutesEditedAt ?? this.minutesEditedAt),
    );
  }
```

In `toRow()` add:

```dart
        'minutes_edited_at': minutesEditedAt?.millisecondsSinceEpoch,
```

In `fromRow()` add:

```dart
        minutesEditedAt: row['minutes_edited_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                row['minutes_edited_at'] as int),
```

In `packages/core/lib/src/meeting_repository.dart`: bump `schemaVersion` to `4`, add the column to `onCreate`'s `CREATE TABLE` (after `status TEXT NOT NULL`, as `minutes_edited_at INTEGER`), and append to `onUpgrade`:

```dart
    if (oldVersion < 4) {
      await db.execute(
          'ALTER TABLE meetings ADD COLUMN minutes_edited_at INTEGER');
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `melos run analyze && melos run test`
Expected: clean; core tests green including the new migration test.

- [ ] **Step 5: Commit**

```bash
git add packages/core
git commit -m "feat(core): persist minutesEditedAt (schema v4)"
```

---

### Task 3: Gate the generation paths (and fix the regenerate data-loss path)

This task changes behaviour but adds no new UI: a thin transcript simply stops producing minutes, falling back to the existing "No summary yet" state. Task 5 gives it a proper explanation.

**Files:**
- Modify: `apps/mobile/lib/screens/transcript_screen.dart:195` (`_generateOverview`), `:257` (`_maybeAutoGenerate`), `:354` (`_regenerate`)
- Modify: `apps/mobile/test/screens/transcript_screen_test.dart:16-27` (`_meeting` helper) and `:165`
- Modify: `apps/mobile/test/privacy_gate_test.dart:55`

**Interfaces:**
- Consumes: `SummarizeGate.assess`, `GateVerdict`, `GateOutcome` from Task 1.
- Produces: `_TranscriptScreenState._verdict` (`GateVerdict` getter over the current meeting), `_TranscriptScreenState._overrideGate` (`bool`, one-shot, not persisted).

**Fixture migration comes first, and it is not cosmetic.** Existing fixtures use `'Alice: ship the beta Friday.'` (5 words) and rely on generation running. `privacy_gate_test.dart` deliberately opens a meeting with no minutes so the auto-generate pass runs offline — its comment calls that "the strongest form of this privacy assertion". With a 30-word floor and an unchanged fixture, that test keeps passing while silently exercising nothing. Migrate the fixtures in the same task that adds the gate.

- [ ] **Step 1: Migrate the shared fixtures to a sufficient transcript**

In `apps/mobile/test/screens/transcript_screen_test.dart`, add a shared constant near the top and use it in `_meeting()` and in the inline `Meeting` at line ~165:

```dart
/// A transcript comfortably over SummarizeGate.minWords (30), so the tests
/// that assert generation actually reach the model. Keep it >= 30 words.
const _richTranscript =
    'Alice: I think we should ship the beta on Friday if the login screen is '
    'ready. Bob: I can finish the login screen by Thursday evening. Alice: '
    'Carol, could you write the release notes for it? Carol: Yes, I will have '
    'them ready on Friday morning. Bob: We also agreed to postpone the '
    'analytics work to the next sprint.';
```

Replace `transcript: 'Alice: ship the beta Friday.'` with `transcript: _richTranscript` in both places. Do the same at `apps/mobile/test/privacy_gate_test.dart:55`, adding a matching local constant with the same comment about why length matters.

- [ ] **Step 2: Run the suite to confirm it is still green before behaviour changes**

Run: `cd apps/mobile && flutter test`
Expected: PASS — 56 tests. This proves the fixture swap alone changed nothing.

- [ ] **Step 3: Write the failing tests for the gate**

Add to `apps/mobile/test/screens/transcript_screen_test.dart`. `_CountingAiEngine` already exists in this file — reuse it.

```dart
  testWidgets('a thin transcript never reaches the model', (tester) async {
    final m = Meeting(
      id: 1,
      title: 'Meeting 10/7 09:00',
      createdAt: DateTime(2026, 7, 10),
      audioPath: '',
      durationMs: 13000,
      transcript: 'So is it working?',
    );
    final repo = FakeMeetingRepository([m]);
    final engine = _CountingAiEngine();
    await _pump(tester, meeting: m, repo: repo, engine: engine);

    // The regression: four words used to produce a full fabricated meeting.
    expect(engine.summarizeCalls, 0);
    expect((await repo.byId(1))?.minutes, anyOf(isNull, isEmpty));
  });

  testWidgets('a sparse long recording never reaches the model',
      (tester) async {
    final m = Meeting(
      id: 1,
      title: 'Meeting 10/7 09:00',
      createdAt: DateTime(2026, 7, 10),
      audioPath: '',
      durationMs: 18 * 60 * 1000,
      transcript: List.generate(40, (i) => 'word$i').join(' '),
    );
    final repo = FakeMeetingRepository([m]);
    final engine = _CountingAiEngine();
    await _pump(tester, meeting: m, repo: repo, engine: engine);

    expect(engine.summarizeCalls, 0);
  });

  testWidgets('a blocked regenerate preserves existing minutes',
      (tester) async {
    // The data-loss path: _regenerate used to clear minutes *before* checking
    // whether it could generate anything to replace them with.
    final m = Meeting(
      id: 1,
      title: 'Kept Name',
      createdAt: DateTime(2026, 7, 10),
      audioPath: '',
      durationMs: 13000,
      transcript: 'So is it working?',
      minutes: '### Summary\nMinutes generated before the guard existed.',
    );
    final repo = FakeMeetingRepository([m]);
    await _pump(tester, meeting: m, repo: repo, engine: _CountingAiEngine());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Regenerate'));
    await tester.pumpAndSettle();

    final saved = await repo.byId(1);
    expect(saved?.minutes,
        '### Summary\nMinutes generated before the guard existed.');
  });
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `cd apps/mobile && flutter test test/screens/transcript_screen_test.dart`
Expected: FAIL — the model is still called (`summarizeCalls` is 1) and the regenerate test finds minutes cleared to `''`.

- [ ] **Step 5: Implement the gate in the screen**

Add the import and state to `apps/mobile/lib/screens/transcript_screen.dart`:

```dart
import 'package:privoice_ai/privoice_ai.dart';
```

```dart
  /// One-shot "Summarize anyway" override. Deliberately not persisted: it
  /// applies to this visit only.
  bool _overrideGate = false;

  GateVerdict get _verdict => SummarizeGate.assess(
        transcript: _transcript,
        durationMs: _meeting.durationMs,
      );

  /// Whether generation is allowed to run at all right now.
  bool get _mayGenerate => _overrideGate || _verdict.sufficient;
```

Guard `_generateOverview` — replace its first line:

```dart
  Future<void> _generateOverview() async {
    if (_busy || _transcript.isEmpty) return;
    if (!_mayGenerate) return;
```

Guard `_maybeAutoGenerate` — add after the existing transcript/model check:

```dart
    if (_transcript.isEmpty || !_manager.llmReady) return;
    if (!_mayGenerate) return;
```

Fix `_regenerate` so it cannot clear minutes it will not replace:

```dart
  Future<void> _regenerate() async {
    // Check the gate *before* clearing: a blocked regenerate must leave
    // existing minutes intact rather than wiping them and putting nothing back.
    if (!_mayGenerate) {
      setState(() {}); // Surface the blocked state; keep the minutes.
      return;
    }
    _meeting = _meeting.copyWith(minutes: '', resetMinutesEdited: true);
    await _generateOverview();
  }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `melos run analyze && melos run test`
Expected: clean; all green, including the three new tests and the migrated fixtures.

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/screens/transcript_screen.dart apps/mobile/test/screens/transcript_screen_test.dart apps/mobile/test/privacy_gate_test.dart
git commit -m "fix(mobile): never summarize a thin transcript; keep minutes on blocked regenerate"
```

---

### Task 4: Extract the Overview tab (pure refactor)

No behaviour change. Tests must stay green without being edited — that is the proof the move was faithful.

**Files:**
- Create: `apps/mobile/lib/screens/overview_tab.dart`
- Modify: `apps/mobile/lib/screens/transcript_screen.dart`

**Interfaces:**
- Consumes: `GateVerdict` (Task 1), `_TranscriptScreenState` fields.
- Produces: `class OverviewTab extends StatelessWidget` with named params:
  `Meeting meeting`, `GateVerdict verdict`, `bool busy`, `bool genFailed`,
  `String busyLabel`, `double progress`, `String streaming`, `bool preparing`,
  `bool overridden`, `Future<void> Function() onGenerate`,
  `Future<void> Function() onRegenerate`,
  `Future<void> Function(int index, bool done) onToggleItem`.
  Also moves `GeneratingView`, `RevealFade`, `AnimatedIn`, and `ActionList`
  into this file, renamed without the leading underscore so the new file can
  export them.

- [ ] **Step 1: Move the code**

Cut from `transcript_screen.dart` into `overview_tab.dart`: the body of `_overviewTab`, plus the private widgets `_GeneratingView`, `_RevealFade`, `_AnimatedIn`, `_ActionList`. Rename them to `GeneratingView`, `RevealFade`, `AnimatedIn`, `ActionList` (they are now used across files). Turn `_overviewTab(scheme)` into `OverviewTab`'s `build`, replacing each `_x` reference with the corresponding constructor param and each `_y()` call with the matching callback.

In `transcript_screen.dart`, the tab body becomes:

```dart
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
    );
  }
```

Keep `_maybeAutoGenerate()` being called from the tab builder, as today — moving it would change when generation kicks off.

- [ ] **Step 2: Run tests to verify nothing changed**

Run: `melos run analyze && melos run test`
Expected: clean; all green **with no test edits**. If a test needed changing, the move was not faithful — fix the move, not the test.

- [ ] **Step 3: Confirm the file shrank**

Run: `wc -l apps/mobile/lib/screens/transcript_screen.dart apps/mobile/lib/screens/overview_tab.dart`
Expected: `transcript_screen.dart` well under its previous 632 lines.

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/screens/overview_tab.dart apps/mobile/lib/screens/transcript_screen.dart
git commit -m "refactor(mobile): extract OverviewTab from transcript_screen"
```

---

### Task 5: Blocked-state UI + "Summarize anyway"

**Files:**
- Modify: `apps/mobile/lib/screens/overview_tab.dart`
- Modify: `apps/mobile/lib/screens/transcript_screen.dart` (the override setter)
- Test: `apps/mobile/test/screens/transcript_screen_test.dart`

**Interfaces:**
- Consumes: `OverviewTab` params from Task 4, `GateVerdict`/`GateOutcome` from Task 1.
- Produces: `OverviewTab` gains `VoidCallback onSummarizeAnyway`; `_TranscriptScreenState._summarizeAnyway()` sets `_overrideGate = true` then calls `_generateOverview()`.

**Exact copy** (do not paraphrase):
- Heading: `Not enough speech to summarize`
- `tooFewWords` reason: `Only 4 words in 0:13.` — i.e. `Only $wordCount words in $mmss.`
- `tooSparse` reason: `18 minutes of audio but only 40 words — mostly silence.` — i.e. `$minutes minutes of audio but only $wordCount words — mostly silence.`
- Button: `Summarize anyway`
- Above the transcript preview: `What was recorded`

- [ ] **Step 1: Write the failing tests**

```dart
  testWidgets('blocked state explains itself with real numbers',
      (tester) async {
    final m = Meeting(
      id: 1,
      title: 'Meeting 10/7 09:00',
      createdAt: DateTime(2026, 7, 10),
      audioPath: '',
      durationMs: 13000,
      transcript: 'So is it working?',
    );
    await _pump(tester,
        meeting: m, repo: FakeMeetingRepository([m]), engine: _CountingAiEngine());
    await tester.pumpAndSettle();

    expect(find.text('Not enough speech to summarize'), findsOneWidget);
    expect(find.text('Only 4 words in 0:13.'), findsOneWidget);
    // The transcript is never hidden from the user.
    expect(find.textContaining('So is it working?'), findsWidgets);
    expect(find.text('Summarize anyway'), findsOneWidget);
  });

  testWidgets('Summarize anyway overrides the gate and generates',
      (tester) async {
    final m = Meeting(
      id: 1,
      title: 'Meeting 10/7 09:00',
      createdAt: DateTime(2026, 7, 10),
      audioPath: '',
      durationMs: 13000,
      transcript: 'So is it working?',
    );
    final repo = FakeMeetingRepository([m]);
    final engine = _CountingAiEngine();
    await _pump(tester, meeting: m, repo: repo, engine: engine);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Summarize anyway'));
    await tester.pumpAndSettle();

    expect(engine.summarizeCalls, 1);
    expect((await repo.byId(1))?.minutes, isNotEmpty);
  });

  testWidgets('sparse recordings get the silence wording', (tester) async {
    final m = Meeting(
      id: 1,
      title: 'Meeting 10/7 09:00',
      createdAt: DateTime(2026, 7, 10),
      audioPath: '',
      durationMs: 18 * 60 * 1000,
      transcript: List.generate(40, (i) => 'word$i').join(' '),
    );
    await _pump(tester,
        meeting: m, repo: FakeMeetingRepository([m]), engine: _CountingAiEngine());
    await tester.pumpAndSettle();

    expect(find.text('18 minutes of audio but only 40 words — mostly silence.'),
        findsOneWidget);
  });

  testWidgets('minutes generated before the guard still render',
      (tester) async {
    final m = Meeting(
      id: 1,
      title: 'Kept',
      createdAt: DateTime(2026, 7, 10),
      audioPath: '',
      durationMs: 13000,
      transcript: 'So is it working?',
      minutes: '### Summary\nPre-guard minutes.',
    );
    await _pump(tester,
        meeting: m, repo: FakeMeetingRepository([m]), engine: _CountingAiEngine());
    await tester.pumpAndSettle();

    // The gate governs generation, not display.
    expect(find.textContaining('Pre-guard minutes.'), findsOneWidget);
    expect(find.text('Not enough speech to summarize'), findsNothing);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/mobile && flutter test test/screens/transcript_screen_test.dart`
Expected: FAIL — none of the copy exists yet.

- [ ] **Step 3: Implement the blocked state**

In `overview_tab.dart`, inside `build`, before the existing "nothing cached" branch, add the blocked branch. It must run only when there is nothing to show: `if (!hasMinutes && !hasItems && !busy && !overridden && !verdict.sufficient)`.

```dart
  static String _mmss(int durationMs) {
    final total = (durationMs / 1000).round();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _reason(GateVerdict v, int durationMs) {
    if (v.outcome == GateOutcome.tooSparse) {
      final mins = (durationMs / 60000).round();
      return '$mins minutes of audio but only ${v.wordCount} words '
          '— mostly silence.';
    }
    return 'Only ${v.wordCount} words in ${_mmss(durationMs)}.';
  }
```

The branch renders, in a scrollable `ListView` with the screen's usual `EdgeInsets.fromLTRB(20, 20, 20, 24)` padding:

1. `Icon(Icons.graphic_eq_rounded, size: 48, color: scheme.onSurfaceVariant)`
2. `Text('Not enough speech to summarize', style: textTheme.titleMedium)`
3. `Text(_reason(verdict, meeting.durationMs), style: TextStyle(color: scheme.onSurfaceVariant))`
4. `TextButton('Summarize anyway')` → `onSummarizeAnyway`
5. `Text('What was recorded', style: textTheme.titleSmall)` then
   `SelectableText(meeting.transcript ?? '')`

Add the param to `OverviewTab`'s constructor and field list:

```dart
  final VoidCallback onSummarizeAnyway;
```

In `transcript_screen.dart`:

```dart
  Future<void> _summarizeAnyway() async {
    setState(() => _overrideGate = true);
    await _generateOverview();
  }
```

and pass `onSummarizeAnyway: _summarizeAnyway` into `OverviewTab`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `melos run analyze && melos run test`
Expected: clean, all green.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/screens apps/mobile/test/screens/transcript_screen_test.dart
git commit -m "feat(mobile): explain why a recording was too thin to summarize"
```

---

### Task 6: Minutes editor

**Files:**
- Create: `apps/mobile/lib/screens/minutes_editor_screen.dart`
- Modify: `apps/mobile/lib/screens/overview_tab.dart` (Edit affordance), `apps/mobile/lib/screens/transcript_screen.dart` (open + save)
- Test: `apps/mobile/test/screens/minutes_editor_test.dart`

**Interfaces:**
- Consumes: nothing from Task 5 beyond `OverviewTab`.
- Produces: `class MinutesEditorScreen extends StatefulWidget` with `const MinutesEditorScreen({super.key, required this.initialText})` and `final String initialText`. Pops `String?` — the new text on Save, `null` on Cancel. `OverviewTab` gains `VoidCallback onEditMinutes`. `_TranscriptScreenState._editMinutes()` pushes it and persists the result with `minutesEditedAt: DateTime.now()`.

**Exact copy:** app-bar title `Edit minutes`; actions `Save` and `Cancel`; discard dialog title `Discard changes?`, body `Your edits to these minutes will be lost.`, buttons `Keep editing` and `Discard`.

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/screens/minutes_editor_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/minutes_editor_screen.dart';

Future<String?> _open(WidgetTester tester, String initial) async {
  String? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () async {
          result = await Navigator.of(context).push<String>(
            MaterialPageRoute(
              builder: (_) => MinutesEditorScreen(initialText: initial),
            ),
          );
        },
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('shows the raw Markdown for editing', (tester) async {
    await _open(tester, '### Summary\nOriginal text.');
    expect(find.text('Edit minutes'), findsOneWidget);
    expect(find.text('### Summary\nOriginal text.'), findsOneWidget);
  });

  testWidgets('Save pops the edited text', (tester) async {
    await _open(tester, 'before');
    await tester.enterText(find.byType(TextField), 'after');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // The route is gone and the edited text came back.
    expect(find.byType(MinutesEditorScreen), findsNothing);
  });

  testWidgets('Cancel with no changes pops immediately without a dialog',
      (tester) async {
    await _open(tester, 'before');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(MinutesEditorScreen), findsNothing);
  });

  testWidgets('Cancel with unsaved changes confirms first', (tester) async {
    await _open(tester, 'before');
    await tester.enterText(find.byType(TextField), 'edited');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    // Still editing, text preserved.
    expect(find.byType(MinutesEditorScreen), findsOneWidget);
    expect(find.text('edited'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(MinutesEditorScreen), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/screens/minutes_editor_test.dart`
Expected: FAIL — `minutes_editor_screen.dart` does not exist.

- [ ] **Step 3: Implement the editor**

Create `apps/mobile/lib/screens/minutes_editor_screen.dart`:

```dart
import 'package:flutter/material.dart';

/// Full-screen plain-text editor for a meeting's minutes.
///
/// The minutes are stored and rendered as Markdown, and this edits the raw
/// source: a full-screen field keeps the keyboard from fighting the layout on
/// long minutes, which inline editing in the Overview tab could not.
///
/// Pops the edited text on Save, or null on Cancel.
class MinutesEditorScreen extends StatefulWidget {
  const MinutesEditorScreen({super.key, required this.initialText});

  final String initialText;

  @override
  State<MinutesEditorScreen> createState() => _MinutesEditorScreenState();
}

class _MinutesEditorScreenState extends State<MinutesEditorScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _dirty => _controller.text != widget.initialText;

  Future<void> _cancel() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your edits to these minutes will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit minutes'),
        leading: TextButton(onPressed: _cancel, child: const Text('Cancel')),
        leadingWidth: 88,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: TextField(
          controller: _controller,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(border: InputBorder.none),
          style: const TextStyle(fontSize: 15.5, height: 1.5),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/screens/minutes_editor_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 5: Wire it into the Overview tab**

Add to `OverviewTab`: `final VoidCallback onEditMinutes;`, and beside the existing Regenerate control render an Edit button — `TextButton.icon(onPressed: onEditMinutes, icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Edit'))`. Only show it when minutes exist.

In `transcript_screen.dart`:

```dart
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
```

- [ ] **Step 6: Write and run the wiring test**

Add to `apps/mobile/test/screens/transcript_screen_test.dart`:

```dart
  testWidgets('editing minutes persists the text and stamps minutesEditedAt',
      (tester) async {
    final m = _meeting(minutes: '### Summary\nOriginal.');
    final repo = FakeMeetingRepository([m]);
    await _pump(tester, meeting: m, repo: repo);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '### Summary\nMine.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = await repo.byId(1);
    expect(saved?.minutes, '### Summary\nMine.');
    expect(saved?.minutesEditedAt, isNotNull);
  });
```

Run: `melos run analyze && melos run test`
Expected: clean, all green.

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/screens apps/mobile/test/screens
git commit -m "feat(mobile): editable minutes via a full-screen Markdown editor"
```

---

### Task 7: Editable action items (add / edit / delete)

**Files:**
- Create: `apps/mobile/lib/widgets/action_item_list.dart`
- Modify: `apps/mobile/lib/screens/overview_tab.dart` (use the new widget, drop `ActionList`), `apps/mobile/lib/screens/transcript_screen.dart` (mutation callbacks)
- Test: `apps/mobile/test/widgets/action_item_list_test.dart`

**Interfaces:**
- Consumes: `ActionItem` from `privoice_core`.
- Produces: `class ActionItemList extends StatelessWidget` with named params
  `List<ActionItem> items`, `Future<void> Function(int index, bool done) onToggle`,
  `Future<void> Function(int index, String text) onEditText`,
  `Future<void> Function(String text) onAdd`,
  `Future<void> Function(int index) onDelete`,
  `Future<void> Function(int oldIndex, int newIndex) onReorder` (wired in Task 8).
  `_TranscriptScreenState` gains `_editItemText`, `_addItem`, `_deleteItem`.

**Behaviour change to be explicit about:** the old `ActionList` sorted done items to the bottom, so the displayed order was derived rather than stored. That makes user-controlled ordering meaningless, so **the auto-sort is removed** — items now display in stored order, which is what Task 8 lets the user set. Check whether `'checking an action item persists done and survives rebuild'` relies on the sort; if it asserts positions rather than persistence, update it to assert persistence.

**Exact copy:** `+ Add item`; edit dialog title `Edit action item`, buttons `Cancel` and `Save`; add dialog title `New action item`, buttons `Cancel` and `Add`; delete affordance is an `IconButton` with `tooltip: 'Delete item'`.

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/widgets/action_item_list_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/action_item_list.dart';
import 'package:privoice_core/privoice_core.dart';

void main() {
  late List<ActionItem> items;
  late List<String> log;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ActionItemList(
          items: items,
          onToggle: (i, done) async => log.add('toggle:$i:$done'),
          onEditText: (i, text) async => log.add('edit:$i:$text'),
          onAdd: (text) async => log.add('add:$text'),
          onDelete: (i) async => log.add('delete:$i'),
          onReorder: (a, b) async => log.add('reorder:$a:$b'),
        ),
      ),
    ));
  }

  setUp(() {
    log = [];
    items = const [
      ActionItem(text: 'Bob: finish login'),
      ActionItem(text: 'Carol: release notes', done: true),
    ];
  });

  testWidgets('renders items in stored order, not done-last order',
      (tester) async {
    await pump(tester);
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    // 'Bob' before 'Carol' is stored order; the old widget sank done items.
    expect(texts.indexOf('Bob: finish login'),
        lessThan(texts.indexOf('Carol: release notes')));
  });

  testWidgets('tapping the checkbox reports a toggle', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(log, contains('toggle:0:true'));
  });

  testWidgets('editing an item reports the new text', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Bob: finish login'));
    await tester.pumpAndSettle();
    expect(find.text('Edit action item'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Bob: finish login by Thu');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(log, contains('edit:0:Bob: finish login by Thu'));
  });

  testWidgets('adding an item reports the text', (tester) async {
    await pump(tester);
    await tester.tap(find.text('+ Add item'));
    await tester.pumpAndSettle();
    expect(find.text('New action item'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Dave: book the room');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(log, contains('add:Dave: book the room'));
  });

  testWidgets('adding an empty item is ignored', (tester) async {
    await pump(tester);
    await tester.tap(find.text('+ Add item'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(log, isEmpty);
  });

  testWidgets('deleting an item reports its index', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Delete item').first);
    await tester.pumpAndSettle();
    expect(log, contains('delete:0'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/widgets/action_item_list_test.dart`
Expected: FAIL — `action_item_list.dart` does not exist.

- [ ] **Step 3: Implement the list**

Create `apps/mobile/lib/widgets/action_item_list.dart` with a `StatelessWidget` that renders, for each item in **stored order**: a `Checkbox` (→ `onToggle`), the text wrapped in an `InkWell` opening the edit dialog (→ `onEditText`, ignoring an empty result), and an `IconButton(icon: Icon(Icons.close_rounded), tooltip: 'Delete item')` (→ `onDelete`). Done items keep today's styling: `color: scheme.onSurfaceVariant` and `decoration: TextDecoration.lineThrough`. Below the rows, a `TextButton` labelled `+ Add item` opens the add dialog (→ `onAdd`, ignoring blank/whitespace-only input, trimming before reporting).

Both dialogs follow the pattern already used by the rename dialog at the bottom of `transcript_screen.dart`: a small `StatefulWidget` owning its own `TextEditingController` so the framework disposes it after the route's exit animation. Reuse that shape rather than inventing a new one.

In `transcript_screen.dart` add the mutation handlers, each persisting immediately (matching `_toggleItem`):

```dart
  Future<void> _editItemText(int index, String text) async {
    final items = List<ActionItem>.of(_meeting.actionItems);
    items[index] = items[index].copyWith(text: text);
    setState(() => _meeting = _meeting.copyWith(actionItems: items));
    await widget.repository.update(_meeting);
  }

  Future<void> _addItem(String text) async {
    final items = List<ActionItem>.of(_meeting.actionItems)
      ..add(ActionItem(text: text));
    setState(() => _meeting = _meeting.copyWith(actionItems: items));
    await widget.repository.update(_meeting);
  }

  Future<void> _deleteItem(int index) async {
    final items = List<ActionItem>.of(_meeting.actionItems)..removeAt(index);
    setState(() => _meeting = _meeting.copyWith(actionItems: items));
    await widget.repository.update(_meeting);
  }
```

Replace `ActionList` with `ActionItemList` in `overview_tab.dart`, threading the new callbacks through as `OverviewTab` params. Delete the now-unused `ActionList`. The action-items section must render whenever items exist **or** minutes exist, so `+ Add item` is reachable on a meeting whose model returned no items.

- [ ] **Step 4: Run tests to verify they pass**

Run: `melos run analyze && melos run test`
Expected: clean, all green.

- [ ] **Step 5: Add the persistence test**

Add to `apps/mobile/test/screens/transcript_screen_test.dart`:

```dart
  testWidgets('adding, editing and deleting action items all persist',
      (tester) async {
    final m = _meeting(
      minutes: '### Summary\nCached.',
      items: const [ActionItem(text: 'Bob: finish login')],
    );
    final repo = FakeMeetingRepository([m]);
    await _pump(tester, meeting: m, repo: repo);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bob: finish login'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Bob: finish login by Thu');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await repo.byId(1))?.actionItems.single.text,
        'Bob: finish login by Thu');

    await tester.tap(find.text('+ Add item'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Dave: book the room');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect((await repo.byId(1))?.actionItems, hasLength(2));

    await tester.tap(find.byTooltip('Delete item').first);
    await tester.pumpAndSettle();
    expect((await repo.byId(1))?.actionItems.single.text,
        'Dave: book the room');
  });
```

Run: `melos run analyze && melos run test`
Expected: clean, all green.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/widgets/action_item_list.dart apps/mobile/lib/screens apps/mobile/test
git commit -m "feat(mobile): add, edit and delete action items"
```

---

### Task 8: Reorder action items

Kept separate because `ReorderableListView` nested in the Overview tab's scroll view is the riskiest change in this slice, and it can be dropped without affecting Tasks 1–7.

**Files:**
- Modify: `apps/mobile/lib/widgets/action_item_list.dart`
- Modify: `apps/mobile/lib/screens/transcript_screen.dart` (`_reorderItems`)
- Test: `apps/mobile/test/widgets/action_item_list_test.dart`, `apps/mobile/test/screens/transcript_screen_test.dart`

**Interfaces:**
- Consumes: `ActionItemList.onReorder` (already in the Task 7 signature, so no signature change).
- Produces: `_TranscriptScreenState._reorderItems(int oldIndex, int newIndex)`.

- [ ] **Step 1: Write the failing test**

Add to `apps/mobile/test/widgets/action_item_list_test.dart`:

```dart
  testWidgets('dragging an item reports a reorder', (tester) async {
    items = const [
      ActionItem(text: 'first'),
      ActionItem(text: 'second'),
      ActionItem(text: 'third'),
    ];
    await pump(tester);

    // Drag 'first' down past 'second'.
    final handle = find.byIcon(Icons.drag_handle_rounded).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(log.where((e) => e.startsWith('reorder:')), isNotEmpty);
  });
```

And to `apps/mobile/test/screens/transcript_screen_test.dart`, a persistence test that calls the handler directly rather than simulating a drag (drag gestures inside a nested scroll view are brittle; the widget-level test above covers the gesture):

```dart
  testWidgets('reordering action items persists the new order', (tester) async {
    final m = _meeting(
      minutes: '### Summary\nCached.',
      items: const [
        ActionItem(text: 'first'),
        ActionItem(text: 'second'),
      ],
    );
    final repo = FakeMeetingRepository([m]);
    await _pump(tester, meeting: m, repo: repo);
    await tester.pumpAndSettle();

    final list = tester.widget<ActionItemList>(find.byType(ActionItemList));
    await list.onReorder(0, 2); // ReorderableListView's post-removal index
    await tester.pumpAndSettle();

    final saved = await repo.byId(1);
    expect(saved?.actionItems.map((i) => i.text).toList(),
        ['second', 'first']);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/mobile && flutter test test/widgets/action_item_list_test.dart test/screens/transcript_screen_test.dart`
Expected: FAIL — no drag handle, and `onReorder` does nothing.

- [ ] **Step 3: Implement reordering**

Convert `ActionItemList`'s rows to a `ReorderableListView` with `shrinkWrap: true`, `physics: const NeverScrollableScrollPhysics()`, and `buildDefaultDragHandles: false`, giving each row a `ReorderableDragStartListener` wrapping `Icon(Icons.drag_handle_rounded)`. Every child needs a stable `Key` — use `ValueKey('action-$index')`. Keep `+ Add item` **outside** the reorderable list.

`onReorder` passes indices straight through; the screen does the index fix-up, since `ReorderableListView` reports `newIndex` as if the dragged item were still present:

```dart
  Future<void> _reorderItems(int oldIndex, int newIndex) async {
    final items = List<ActionItem>.of(_meeting.actionItems);
    // ReorderableListView reports newIndex before the removal is applied.
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    setState(() => _meeting = _meeting.copyWith(actionItems: items));
    await widget.repository.update(_meeting);
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `melos run analyze && melos run test`
Expected: clean, all green.

If the nested `ReorderableListView` fights the outer `ListView` (unbounded-height or scroll-conflict exceptions), fall back to the documented alternative: keep the plain list and add a reorder-mode toggle that swaps in the reorderable list full-screen. Do not leave a half-working drag.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/widgets/action_item_list.dart apps/mobile/lib/screens/transcript_screen.dart apps/mobile/test
git commit -m "feat(mobile): drag to reorder action items"
```

---

### Task 9: Regenerate confirmation

**Files:**
- Modify: `apps/mobile/lib/screens/transcript_screen.dart` (`_regenerate`)
- Test: `apps/mobile/test/screens/transcript_screen_test.dart`

**Interfaces:**
- Consumes: `Meeting.minutesEditedAt` (Task 2), `_mayGenerate` (Task 3).
- Produces: no new public API.

**Exact copy:** dialog title `Replace your edits?`, body `Regenerating replaces the minutes you edited. This can't be undone.`, buttons `Cancel` and `Regenerate`.

**Known limitation, by design:** item-only edits made in a previous app session do not trigger the warning — the durable signal is `minutesEditedAt` alone. Documented in the spec; do not add a column for it.

- [ ] **Step 1: Write the failing tests**

```dart
  testWidgets('Regenerate warns when minutes were hand-edited', (tester) async {
    final m = _meeting(minutes: '### Summary\nMine.')
        .copyWith(minutesEditedAt: DateTime(2026, 7, 27));
    final repo = FakeMeetingRepository([m]);
    final engine = _CountingAiEngine();
    await _pump(tester, meeting: m, repo: repo, engine: engine);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Regenerate'));
    await tester.pumpAndSettle();
    expect(find.text('Replace your edits?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(engine.summarizeCalls, 0);
    expect((await repo.byId(1))?.minutes, '### Summary\nMine.');
  });

  testWidgets('confirming the warning regenerates and clears the edit stamp',
      (tester) async {
    final m = _meeting(minutes: '### Summary\nMine.')
        .copyWith(minutesEditedAt: DateTime(2026, 7, 27));
    final repo = FakeMeetingRepository([m]);
    final engine = _CountingAiEngine();
    await _pump(tester, meeting: m, repo: repo, engine: engine);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Regenerate'));
    await tester.pumpAndSettle();
    // The confirm button carries the same label as the trigger, so scope the
    // tap to the dialog.
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Regenerate'),
    ));
    await tester.pumpAndSettle();

    expect(engine.summarizeCalls, 1);
    expect((await repo.byId(1))?.minutesEditedAt, isNull);
  });

  testWidgets('Regenerate does not warn when minutes were never edited',
      (tester) async {
    final m = _meeting(minutes: '### Summary\nGenerated.');
    final repo = FakeMeetingRepository([m]);
    await _pump(tester, meeting: m, repo: repo, engine: _CountingAiEngine());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Regenerate'));
    await tester.pumpAndSettle();
    expect(find.text('Replace your edits?'), findsNothing);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/mobile && flutter test test/screens/transcript_screen_test.dart`
Expected: FAIL — no dialog appears.

- [ ] **Step 3: Implement the confirmation**

Extend `_regenerate`, keeping the Task 3 gate check first:

```dart
  Future<void> _regenerate() async {
    if (!_mayGenerate) {
      setState(() {});
      return;
    }
    if (_meeting.minutesEditedAt != null) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace your edits?'),
          content: const Text(
              "Regenerating replaces the minutes you edited. This can't be "
              'undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Regenerate'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    _meeting = _meeting.copyWith(minutes: '', resetMinutesEdited: true);
    await _generateOverview();
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `melos run analyze && melos run test`
Expected: clean, all green.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/screens/transcript_screen.dart apps/mobile/test/screens/transcript_screen_test.dart
git commit -m "feat(mobile): confirm before Regenerate discards hand-edited minutes"
```

---

### Task 10: "Transcript only" on Home + STATUS.md

**Files:**
- Modify: `apps/mobile/lib/home_meeting_groups.dart:62` (`metaLine`)
- Modify: `STATUS.md`
- Test: `apps/mobile/test/home_meeting_groups_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: no new API — `metaLine` gains one segment.

**Exact copy:** `Transcript only`.

The subtitle is built by the pure function `metaLine(Meeting, DateTime)`, so this is a unit test, not a widget test.

- [ ] **Step 1: Write the failing test**

Add inside the existing `group('metaLine', ...)` in `apps/mobile/test/home_meeting_groups_test.dart`, using the file's own `_m` helper and `now`:

```dart
    test('transcript but no minutes reads "Transcript only"', () {
      final m = _m(DateTime(2026, 7, 11, 9), ms: 132000);
      expect(metaLine(m, now), '1h ago · 2:12 · Transcript only');
    });

    test('no transcript and no minutes lists neither', () {
      final m = _m(DateTime(2026, 7, 11, 9), ms: 132000, transcript: '');
      expect(metaLine(m, now), '1h ago · 2:12');
    });

    test('minutes win over the transcript-only marker', () {
      final m = _m(DateTime(2026, 7, 11, 9), ms: 132000, minutes: '# x');
      expect(metaLine(m, now), '1h ago · 2:12 · Minutes');
    });
```

Check `_m`'s signature first: if it does not already accept a `transcript`
argument, add an optional one defaulting to a non-empty string, and confirm the
two pre-existing `metaLine` expectations at lines 51-58 still hold — the
`'1h ago · 2:12 · Minutes · 2 actions'` case must be unaffected, since it has
minutes.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/home_meeting_groups_test.dart`
Expected: FAIL — got `1h ago · 2:12`, wanted `1h ago · 2:12 · Transcript only`.

- [ ] **Step 3: Implement the subtitle**

In `apps/mobile/lib/home_meeting_groups.dart`, extend `metaLine`:

```dart
  final parts = <String>[rel, formatDuration(m.durationMs)];
  if ((m.minutes ?? '').isNotEmpty) {
    parts.add('Minutes');
  } else if ((m.transcript ?? '').trim().isNotEmpty) {
    // Transcribed but deliberately not summarized — usually the guard.
    parts.add('Transcript only');
  }
  if (m.actionItems.isNotEmpty) parts.add('${m.actionItems.length} actions');
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `melos run analyze && melos run test`
Expected: clean, all green.

- [ ] **Step 5: Update STATUS.md**

Per `CLAUDE.md`, STATUS.md is part of *done*:
- Bump **Last updated** to the current date.
- Add a row to the Build slices table for this slice, marked ✅ only once verified on a device or simulator — not merely because tests pass.
- In the mobile **Now** line, record the guard and the editable minutes/actions.
- Note the thresholds (30 words / 20 wpm) under Environment facts so nobody re-derives them.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile STATUS.md
git commit -m "feat(mobile): mark transcript-only meetings on Home; update STATUS"
```

---

### Task 11: Verify on a device

Tests passing is not the same as the feature working. `CLAUDE.md` requires ✅ to mean verified.

- [ ] **Step 1: Build and run on the iOS Simulator**

```bash
export PATH="/opt/homebrew/bin:$HOME/.pub-cache/bin:$PATH"
cd apps/mobile && flutter run -d 754FF40D-1C66-4699-A426-06FD2D091895 --debug
```

- [ ] **Step 2: Exercise the guard on the real fabricated meeting**

The simulator already holds the "So is it working?" meeting with fabricated minutes. Confirm: its existing minutes still render (the gate governs generation, not display), and tapping Regenerate shows the blocked explanation **without** destroying those minutes.

- [ ] **Step 3: Exercise a fresh thin recording**

Record ~10 seconds saying a few words. Confirm Overview shows `Not enough speech to summarize`, the word count and duration are right, the transcript is visible, and `Summarize anyway` produces minutes when tapped.

- [ ] **Step 4: Exercise editing**

Edit the minutes, save, reopen the meeting, and confirm the text persisted. Add, edit, delete, and reorder action items, then relaunch the app and confirm the order and text survived. Hit Regenerate and confirm the "Replace your edits?" warning appears.

- [ ] **Step 5: Build for Android to confirm nothing platform-specific broke**

```bash
cd apps/mobile && flutter build apk --debug
```

- [ ] **Step 6: Flip STATUS.md to verified and commit**

```bash
git add STATUS.md
git commit -m "docs(status): trustworthy minutes verified on simulator"
```

---

## Self-Review

**Spec coverage:** `SummarizeGate` + thresholds → Task 1. `minutesEditedAt` + v4 → Task 2. Gate at both entry points + the regenerate data-loss fix → Task 3. Screen split → Task 4. Blocked UI, exact copy, "Summarize anyway", derived-not-persisted, existing minutes preserved → Task 5. Minutes editor + stamp → Task 6. Item add/edit/delete + independence → Task 7. Reorder + the done-last-sort conflict → Task 7/8. Regenerate confirm + documented limitation → Task 9. Home subtitle + STATUS → Task 10. Device verification → Task 11. Every spec test listed in "Testing" maps to a task. No gaps.

**Type consistency:** `GateVerdict`/`GateOutcome`/`SummarizeGate.assess` are named identically in Tasks 1, 3, 4, 5. `resetMinutesEdited` is introduced in Task 2 and used in Tasks 3 and 9. `ActionItemList`'s six callbacks are declared once in Task 7 and `onReorder` is used unchanged in Task 8. `OverviewTab` accumulates params across Tasks 4, 5, 6, 7 — each task states the ones it adds.

**Placeholder scan:** one placeholder was found in the first draft (Task 10's
test was a comment block describing a test rather than a test) and has been
replaced with real code against the actual `metaLine` function — which also
moved the change from `home_screen.dart` to `home_meeting_groups.dart:62` and
turned a widget test into a unit test.

**Remaining judgement calls left to the implementer, deliberately:** Task 7 says
to check whether the existing `'checking an action item persists done and
survives rebuild'` test depends on the removed done-last sort, and Task 2's
migration test says to match the file's existing in-memory database helper.
Both require reading a file's current contents; inventing code against an
unread structure would be worse than naming the check.
