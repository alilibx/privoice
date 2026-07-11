# R6 — Meeting screen redesign (Overview + Transcript) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the meeting screen around an Overview-first dashboard (AI title → minutes → checkable action items) that auto-generates on open, with inline rename and richer sharing, in the calm-teal language.

**Architecture:** Three layers change. (1) `packages/core` gains an `ActionItem` value type; `Meeting.actionItems` becomes `List<ActionItem>` serialized as JSON with a v2→v3 sqflite migration. (2) `packages/ai` gains a `title(transcript)` engine method + prompt + a pure `cleanTitle` helper; `AiService` exposes `generateTitle`. (3) `apps/mobile` rewrites `transcript_screen.dart` into the Overview/Transcript screen: auto-generate pass, checkable persisted to-dos, inline rename (guarded auto-title), per-section share + disabled Export, persistent Ask entry.

**Tech Stack:** Flutter, Dart, sqflite (+ `sqflite_common_ffi` for tests), fllama (on-device LLM), `share_plus`, `flutter_markdown`. Melos monorepo.

## Global Constraints

- **Privacy invariant:** on-device by default; no network is introduced. Title/minutes/actions are all on-device. The zero-network privacy gate (`apps/mobile/test/privacy_gate_test.dart`) must stay green.
- **Architecture rule:** native/model logic stays in its package behind a Dart interface; the app depends on `AiEngine`/`MeetingRepository`, not implementations. `AiService.actionItems` stays `List<String>`-based — the storage type (`ActionItem`) does not leak into the engine.
- **Default title shape (verbatim):** `record_screen._defaultTitle()` produces `'Meeting ${now.day}/${now.month} $h:$m'` (e.g. `Meeting 11/7 14:30`), where `h`/`m` are 2-digit. Auto-title only overwrites a title matching this shape.
- **Conventions:** conventional commits; TDD (failing test first); `melos run analyze` must stay clean; keep files focused.
- **Verify commands:**
  - Package test: `cd packages/core && flutter test test/<file>`
  - AI package test: `cd packages/ai && flutter test test/<file>`
  - App test: `cd apps/mobile && flutter test test/<path>`
  - Whole suite: `melos run test` · Analyze: `melos run analyze`
  - Env (prepend once per shell): `export PATH="/opt/homebrew/bin:$HOME/.pub-cache/bin:$PATH"; export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"; export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"`

---

## File Structure

**Create:**
- `packages/core/lib/src/action_item.dart` — `ActionItem` value type (text + done) with JSON + equality.
- `packages/core/test/action_item_test.dart` — `ActionItem` JSON/equality tests.
- `packages/ai/lib/src/title.dart` — pure `cleanTitle(raw)` helper.
- `packages/ai/test/title_test.dart` — `cleanTitle` tests.
- `apps/mobile/lib/meeting_share.dart` — pure text-assembly helpers for share/copy.
- `apps/mobile/test/meeting_share_test.dart` — share-text tests.

**Modify:**
- `packages/core/lib/src/meeting.dart` — `actionItems` → `List<ActionItem>`; JSON `toRow`/`fromRow` with legacy fallback; `copyWith`.
- `packages/core/lib/privoice_core.dart` — export `ActionItem`.
- `packages/core/lib/src/meeting_repository.dart` — `schemaVersion` 3 + `onUpgrade` legacy→JSON.
- `packages/core/test/meeting_test.dart` — update to `List<ActionItem>`.
- `packages/core/test/meeting_repository_test.dart` — update usage + add migration test.
- `packages/ai/lib/src/ai_engine.dart` — add `title(transcript)` to the interface.
- `packages/ai/lib/src/on_device_ai_engine.dart` — implement `title`.
- `packages/ai/lib/src/prompts.dart` — add `Prompts.title`.
- `packages/ai/lib/privoice_ai.dart` — export `title.dart`.
- `apps/mobile/lib/ai_service.dart` — add `generateTitle`.
- `apps/mobile/test/fakes/fake_ai_engine.dart` — implement `title`.
- `apps/mobile/lib/screens/transcript_screen.dart` — rewritten across Tasks 4–8.
- `apps/mobile/test/screens/transcript_screen_test.dart` — rewritten for the new screen.

---

## Task 1: `ActionItem` value type + `Meeting.actionItems` → `List<ActionItem>`

**Files:**
- Create: `packages/core/lib/src/action_item.dart`
- Create: `packages/core/test/action_item_test.dart`
- Modify: `packages/core/lib/privoice_core.dart`
- Modify: `packages/core/lib/src/meeting.dart`
- Modify: `packages/core/test/meeting_test.dart`
- Modify: `apps/mobile/lib/screens/transcript_screen.dart` (minimal compile fix only)
- Modify: `packages/core/test/meeting_repository_test.dart` (usage fix only)

**Interfaces:**
- Produces: `class ActionItem { const ActionItem({required String text, bool done = false}); final String text; final bool done; ActionItem copyWith({String? text, bool? done}); Map<String,Object?> toJson(); factory ActionItem.fromJson(Map<String,Object?>); }` and `Meeting.actionItems` is now `List<ActionItem>` (JSON-encoded in the `action_items` TEXT column, with a legacy newline fallback on read).

- [ ] **Step 1: Write the failing `ActionItem` test**

Create `packages/core/test/action_item_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_core/privoice_core.dart';

void main() {
  test('toJson/fromJson round-trips text and done', () {
    const a = ActionItem(text: 'Ship the beta', done: true);
    final back = ActionItem.fromJson(a.toJson());
    expect(back.text, 'Ship the beta');
    expect(back.done, isTrue);
  });

  test('defaults done to false', () {
    const a = ActionItem(text: 'x');
    expect(a.done, isFalse);
  });

  test('fromJson tolerates a missing done key', () {
    final a = ActionItem.fromJson({'text': 'legacy'});
    expect(a.done, isFalse);
  });

  test('copyWith flips done only', () {
    const a = ActionItem(text: 'x');
    final b = a.copyWith(done: true);
    expect(b.text, 'x');
    expect(b.done, isTrue);
  });

  test('value equality', () {
    expect(const ActionItem(text: 'x'), const ActionItem(text: 'x'));
    expect(const ActionItem(text: 'x', done: true),
        isNot(const ActionItem(text: 'x')));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/core && flutter test test/action_item_test.dart`
Expected: FAIL — `ActionItem` is not defined.

- [ ] **Step 3: Create `ActionItem`**

Create `packages/core/lib/src/action_item.dart`:

```dart
/// One action item extracted from a meeting, with a persisted done-state.
class ActionItem {
  const ActionItem({required this.text, this.done = false});

  final String text;
  final bool done;

  ActionItem copyWith({String? text, bool? done}) =>
      ActionItem(text: text ?? this.text, done: done ?? this.done);

  Map<String, Object?> toJson() => {'text': text, 'done': done};

  factory ActionItem.fromJson(Map<String, Object?> json) => ActionItem(
        text: json['text'] as String,
        done: (json['done'] as bool?) ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is ActionItem && other.text == text && other.done == done;

  @override
  int get hashCode => Object.hash(text, done);
}
```

- [ ] **Step 4: Export it**

In `packages/core/lib/privoice_core.dart`, add an export line alongside the existing ones:

```dart
export 'src/action_item.dart';
```

- [ ] **Step 5: Run the `ActionItem` test to verify it passes**

Run: `cd packages/core && flutter test test/action_item_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Write the failing `Meeting` serialization tests**

Replace the body of `packages/core/test/meeting_test.dart` with:

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_core/privoice_core.dart';

void main() {
  test('toRow/fromRow round-trips all fields incl. action items', () {
    final m = Meeting(
      id: 7,
      title: 'Sprint planning',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1720000000000),
      audioPath: '/audio/x.wav',
      durationMs: 123456,
      transcript: 'hello world',
      minutes: '### Summary\nok',
      actionItems: const [
        ActionItem(text: 'a', done: true),
        ActionItem(text: 'b'),
      ],
      status: MeetingStatus.done,
    );

    final back = Meeting.fromRow(m.toRow());

    expect(back.title, 'Sprint planning');
    expect(back.minutes, '### Summary\nok');
    expect(back.actionItems, const [
      ActionItem(text: 'a', done: true),
      ActionItem(text: 'b'),
    ]);
    expect(back.status, MeetingStatus.done);
  });

  test('action items serialize as a JSON array', () {
    final m = Meeting(
      title: 'x',
      audioPath: '',
      durationMs: 0,
      actionItems: const [ActionItem(text: 'a')],
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
    final raw = m.toRow()['action_items'] as String;
    expect(jsonDecode(raw), [
      {'text': 'a', 'done': false}
    ]);
  });

  test('empty action items serialize to null and back to []', () {
    final m = Meeting(
      title: 'x',
      audioPath: '',
      durationMs: 0,
      actionItems: const [],
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
    expect(m.toRow()['action_items'], isNull);
    expect(Meeting.fromRow(m.toRow()).actionItems, isEmpty);
  });

  test('fromRow falls back to legacy newline action_items', () {
    final row = {
      'id': 1,
      'title': 'Legacy',
      'created_at': 0,
      'audio_path': '/a.wav',
      'duration_ms': 0,
      'transcript': 't',
      'minutes': null,
      'action_items': 'do a\ndo b',
      'status': 'done',
    };
    final m = Meeting.fromRow(row);
    expect(m.actionItems,
        const [ActionItem(text: 'do a'), ActionItem(text: 'do b')]);
  });
}
```

- [ ] **Step 7: Run to verify it fails**

Run: `cd packages/core && flutter test test/meeting_test.dart`
Expected: FAIL — `actionItems` expects `List<String>` / type errors.

- [ ] **Step 8: Change the `Meeting` model**

In `packages/core/lib/src/meeting.dart`, add `import 'dart:convert';` and `import 'action_item.dart';` at the top, then apply these changes:

Field type:
```dart
  final List<ActionItem> actionItems;
```

Constructor default stays `this.actionItems = const []` (already correct).

`copyWith` signature + body — change the `actionItems` param type:
```dart
  Meeting copyWith({
    int? id,
    String? title,
    String? transcript,
    String? minutes,
    List<ActionItem>? actionItems,
    MeetingStatus? status,
  }) {
```
(The body line `actionItems: actionItems ?? this.actionItems,` is unchanged.)

`toRow` — replace the `'action_items'` entry:
```dart
        'action_items': actionItems.isEmpty
            ? null
            : jsonEncode(actionItems.map((a) => a.toJson()).toList()),
```

`fromRow` — replace the `actionItems:` argument with a decode helper call:
```dart
        actionItems: _decodeActionItems(row['action_items'] as String?),
```

Add this private static helper to the `Meeting` class (e.g. just after `fromRow`):
```dart
  static List<ActionItem> _decodeActionItems(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    // New format: a JSON array of {text, done}.
    if (raw.trimLeft().startsWith('[')) {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ActionItem.fromJson((e as Map).cast<String, Object?>()))
          .toList();
    }
    // Legacy format: newline-joined strings (pre-v3 rows).
    return raw
        .split('\n')
        .where((s) => s.trim().isNotEmpty)
        .map((s) => ActionItem(text: s))
        .toList();
  }
```

- [ ] **Step 9: Run the `Meeting` test to verify it passes**

Run: `cd packages/core && flutter test test/meeting_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 10: Fix the two remaining `List<String>` consumers so the repo compiles**

The model change breaks two existing usages. Patch them minimally (proper rewrites come later).

In `packages/core/test/meeting_repository_test.dart`, the `update persists minutes and action items` test uses `actionItems: ['do a', 'do b']`. Change it to:
```dart
      actionItems: const [ActionItem(text: 'do a'), ActionItem(text: 'do b')],
```
and its assertion:
```dart
    expect(loaded?.actionItems,
        const [ActionItem(text: 'do a'), ActionItem(text: 'do b')]);
```

In `apps/mobile/lib/screens/transcript_screen.dart`, two spots use the old string list:
- In `_actionItems()`, the line `_meeting = _meeting.copyWith(actionItems: items);` (where `items` is `List<String>`). Change to:
  ```dart
      _meeting = _meeting.copyWith(
          actionItems: items.map((t) => ActionItem(text: t)).toList());
  ```
- In `_minutesTab`, `_ActionChips(items: _meeting.actionItems)` — pass the texts:
  ```dart
          _ActionChips(items: _meeting.actionItems.map((a) => a.text).toList()),
  ```

- [ ] **Step 11: Verify the whole core package + app analyze are green**

Run: `cd packages/core && flutter test`
Expected: PASS (all core tests).
Run: `cd apps/mobile && flutter analyze lib/screens/transcript_screen.dart`
Expected: No issues.

- [ ] **Step 12: Commit**

```bash
git add packages/core/lib/src/action_item.dart packages/core/lib/privoice_core.dart \
  packages/core/lib/src/meeting.dart packages/core/test/action_item_test.dart \
  packages/core/test/meeting_test.dart packages/core/test/meeting_repository_test.dart \
  apps/mobile/lib/screens/transcript_screen.dart
git commit -m "feat(core): ActionItem value type; Meeting.actionItems -> List<ActionItem> (JSON + legacy fallback)"
```

---

## Task 2: Repository v2→v3 migration (legacy newline → JSON)

**Files:**
- Modify: `packages/core/lib/src/meeting_repository.dart`
- Modify: `packages/core/test/meeting_repository_test.dart`

**Interfaces:**
- Consumes: `Meeting.fromRow` JSON/legacy decode (Task 1), `ActionItem`.
- Produces: `SqfliteMeetingRepository.schemaVersion == 3`; `onUpgrade(db, oldVersion, newVersion)` converts any legacy newline `action_items` value to the JSON `[{text,done:false}]` form.

- [ ] **Step 1: Write the failing migration test**

Add to `packages/core/test/meeting_repository_test.dart` (inside `main()`, alongside the others; it uses the already-imported `sqflite_common_ffi`):

```dart
  test('v2->v3 migrates legacy newline action_items to JSON items', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: SqfliteMeetingRepository.onCreate,
        singleInstance: false,
      ),
    );
    // Seed a legacy row exactly as a v2 build would have written it.
    await db.insert('meetings', {
      'title': 'Legacy',
      'created_at': 0,
      'audio_path': '/a.wav',
      'duration_ms': 0,
      'transcript': 't',
      'action_items': 'do a\ndo b',
      'status': 'done',
    });

    await SqfliteMeetingRepository.onUpgrade(db, 2, 3);

    final stored = (await db.query('meetings')).single['action_items'] as String;
    expect(stored.trimLeft().startsWith('['), isTrue); // now JSON

    final repo = SqfliteMeetingRepository.fromDatabase(db);
    final loaded = (await repo.all()).single;
    expect(loaded.actionItems,
        const [ActionItem(text: 'do a'), ActionItem(text: 'do b')]);
    expect(loaded.actionItems.every((a) => !a.done), isTrue);
  });

  test('v2->v3 leaves JSON action_items untouched', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: SqfliteMeetingRepository.onCreate,
        singleInstance: false,
      ),
    );
    await db.insert('meetings', {
      'title': 'New',
      'created_at': 0,
      'audio_path': '/a.wav',
      'duration_ms': 0,
      'transcript': 't',
      'action_items': '[{"text":"keep","done":true}]',
      'status': 'done',
    });

    await SqfliteMeetingRepository.onUpgrade(db, 2, 3);

    final repo = SqfliteMeetingRepository.fromDatabase(db);
    expect((await repo.all()).single.actionItems,
        const [ActionItem(text: 'keep', done: true)]);
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd packages/core && flutter test test/meeting_repository_test.dart -p vm --name migrates`
Expected: FAIL — rows are not migrated (still newline) / `onUpgrade` has no v3 branch.

- [ ] **Step 3: Bump the schema version and add the migration**

In `packages/core/lib/src/meeting_repository.dart`, add `import 'dart:convert';` at the top. Change:
```dart
  static const schemaVersion = 3;
```

Replace `onUpgrade` with:
```dart
  static Future<void> onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE meetings ADD COLUMN minutes TEXT');
      await db.execute('ALTER TABLE meetings ADD COLUMN action_items TEXT');
    }
    if (oldVersion < 3) {
      // action_items moved from newline-joined text to a JSON array of
      // {text, done}. Convert any legacy rows in place; leave JSON rows alone.
      final rows = await db.query('meetings', columns: ['id', 'action_items']);
      for (final row in rows) {
        final raw = row['action_items'] as String?;
        if (raw == null || raw.trim().isEmpty) continue;
        if (raw.trimLeft().startsWith('[')) continue; // already JSON
        final items = raw
            .split('\n')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => {'text': s, 'done': false})
            .toList();
        await db.update(
          'meetings',
          {'action_items': jsonEncode(items)},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
  }
```

- [ ] **Step 4: Run the migration tests to verify they pass**

Run: `cd packages/core && flutter test test/meeting_repository_test.dart`
Expected: PASS (all repo tests, incl. both new migration tests).

- [ ] **Step 5: Commit**

```bash
git add packages/core/lib/src/meeting_repository.dart packages/core/test/meeting_repository_test.dart
git commit -m "feat(core): schema v3 migration — action_items newline -> JSON items"
```

---

## Task 3: `AiEngine.title` + `Prompts.title` + `cleanTitle` + `AiService.generateTitle`

**Files:**
- Create: `packages/ai/lib/src/title.dart`
- Create: `packages/ai/test/title_test.dart`
- Modify: `packages/ai/lib/src/prompts.dart`
- Modify: `packages/ai/lib/src/ai_engine.dart`
- Modify: `packages/ai/lib/src/on_device_ai_engine.dart`
- Modify: `packages/ai/lib/privoice_ai.dart`
- Modify: `apps/mobile/lib/ai_service.dart`
- Modify: `apps/mobile/test/fakes/fake_ai_engine.dart`

**Interfaces:**
- Produces: `String cleanTitle(String raw, {int maxWords = 8})` (pure); `AiEngine.title(String transcript) → Future<String>`; `AiService.generateTitle(String transcript) → Future<String?>` (returns `null` if the model isn't installed or the result is blank).

- [ ] **Step 1: Write the failing `cleanTitle` test**

Create `packages/ai/test/title_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_ai/privoice_ai.dart';

void main() {
  test('strips surrounding quotes and trailing punctuation', () {
    expect(cleanTitle('"Beta Launch Planning."'), 'Beta Launch Planning');
  });

  test('takes only the first line', () {
    expect(cleanTitle('Q3 Roadmap Review\nHere are the notes'),
        'Q3 Roadmap Review');
  });

  test('drops a leading "Title:" label', () {
    expect(cleanTitle('Title: Hiring Sync'), 'Hiring Sync');
  });

  test('caps to maxWords', () {
    expect(cleanTitle('one two three four five', maxWords: 3), 'one two three');
  });

  test('blank stays blank', () {
    expect(cleanTitle('   '), '');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd packages/ai && flutter test test/title_test.dart`
Expected: FAIL — `cleanTitle` not defined.

- [ ] **Step 3: Create `cleanTitle`**

Create `packages/ai/lib/src/title.dart`:

```dart
/// Clean the model's raw title output into a short, single-line title:
/// first line only, no surrounding quotes, no "Title:" label, no trailing
/// punctuation, capped to [maxWords] words.
String cleanTitle(String raw, {int maxWords = 8}) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  s = s.split('\n').first.trim();
  s = s.replaceFirst(RegExp(r'^title\s*[:\-]\s*', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'''^["'“”‘’]+|["'“”‘’]+$'''), '').trim();
  s = s.replaceFirst(RegExp(r'[.\s]+$'), '').trim();
  final words = s.split(RegExp(r'\s+'));
  if (words.length > maxWords) s = words.take(maxWords).join(' ');
  return s;
}
```

- [ ] **Step 4: Export it**

In `packages/ai/lib/privoice_ai.dart`, add:
```dart
export 'src/title.dart';
```

- [ ] **Step 5: Run the `cleanTitle` test to verify it passes**

Run: `cd packages/ai && flutter test test/title_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Add the title prompt**

In `packages/ai/lib/src/prompts.dart`, add this static method inside `class Prompts`:

```dart
  /// Ask for a short, specific meeting title (no date, no quotes).
  static String title(String transcript) {
    return 'Give this meeting a short, specific title of 3 to 6 words in '
        'Title Case. No date, no quotes, no trailing punctuation. Reply with '
        'ONLY the title.\n\nTranscript:\n$transcript';
  }
```

- [ ] **Step 7: Add `title` to the `AiEngine` interface**

In `packages/ai/lib/src/ai_engine.dart`, add to the `abstract class AiEngine` (e.g. after `actionItems`):

```dart
  /// A short, specific meeting title (~3–6 words, no date) derived from the
  /// transcript. Best-effort; returns a trimmed single line.
  Future<String> title(String transcript);
```

- [ ] **Step 8: Implement `title` on the on-device engine**

In `packages/ai/lib/src/on_device_ai_engine.dart`, add `import 'title.dart';` and this method (mirrors `actionItems`):

```dart
  @override
  Future<String> title(String transcript) async {
    if (transcript.trim().isEmpty) return '';
    final out = await _run(
      [ChatMessage.user(Prompts.title(_cap(transcript, 1500)))],
      maxTokens: 24,
      temperature: 0.3,
    );
    return cleanTitle(out);
  }
```

- [ ] **Step 9: Implement `title` on the fake engine + add a title field**

In `apps/mobile/test/fakes/fake_ai_engine.dart`, add a `title` field and method. Change the constructor and add the override:

```dart
  FakeAiEngine({
    this.minutes = '### Summary\nFake minutes for tests.',
    this.items = const ['Alice: ship it'],
    this.answer = 'Fake answer.',
    this.titleText = 'Fake Meeting Title',
  });

  final String minutes;
  final List<String> items;
  final String answer;
  final String titleText;
```
and add:
```dart
  @override
  Future<String> title(String transcript) async => titleText;
```

- [ ] **Step 10: Add `generateTitle` to `AiService`**

In `apps/mobile/lib/ai_service.dart`, add:

```dart
  /// A short AI title for the meeting, or null if the model isn't installed
  /// or the result is blank.
  Future<String?> generateTitle(String transcript) async {
    final e = await _engineOrNull();
    if (e == null) return null;
    final t = (await e.title(transcript)).trim();
    return t.isEmpty ? null : t;
  }
```

- [ ] **Step 11: Verify AI package + app analyze are green**

Run: `cd packages/ai && flutter test`
Expected: PASS (incl. title test). If any other `AiEngine` implementer/fake in the AI package tests exists, add a `title` override there too (search: `grep -rl "implements AiEngine" packages/ai/test`).
Run: `cd apps/mobile && flutter analyze lib/ai_service.dart test/fakes/fake_ai_engine.dart`
Expected: No issues.

- [ ] **Step 12: Commit**

```bash
git add packages/ai/lib/src/title.dart packages/ai/lib/src/prompts.dart \
  packages/ai/lib/src/ai_engine.dart packages/ai/lib/src/on_device_ai_engine.dart \
  packages/ai/lib/privoice_ai.dart packages/ai/test/title_test.dart \
  apps/mobile/lib/ai_service.dart apps/mobile/test/fakes/fake_ai_engine.dart
git commit -m "feat(ai): on-device meeting title generation (Prompts.title + cleanTitle + AiEngine.title)"
```

---

## Task 4: Screen shell — Overview-first tabs, restyle, overflow menu, disabled Export, persistent Ask

**Files:**
- Modify: `apps/mobile/lib/screens/transcript_screen.dart`
- Modify: `apps/mobile/test/screens/transcript_screen_test.dart` (rewrite)

**Interfaces:**
- Consumes: `Meeting` (with `List<ActionItem>`), `AiService`, `MeetingRepository`, `ModelManager`, `AskSheet.show(...)`.
- Produces: a `TranscriptScreen` whose default tab is **Overview** and second is **Transcript**; an app-bar **⋮** overflow menu with Share/Copy/Export (Export disabled); a persistent bottom **Ask** entry. This task renders *cached* minutes + action items only (auto-generate lands in Task 5). The old `_SmartActionBar` is removed.

- [ ] **Step 1: Write the failing structure test**

Replace `apps/mobile/test/screens/transcript_screen_test.dart` with this (drop the old smart-action-bar tests):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/ai_service.dart';
import 'package:mobile/model_manager.dart';
import 'package:mobile/screens/transcript_screen.dart';
import 'package:privoice_core/privoice_core.dart';
import 'package:privoice_models/privoice_models.dart';

import '../fakes/fake_ai_engine.dart';
import '../fakes/fake_meeting_repository.dart';
import '../fakes/fake_model_downloader.dart';

Meeting _meeting({String? minutes, List<ActionItem> items = const []}) => Meeting(
      id: 1,
      title: 'Product sync',
      createdAt: DateTime(2026, 7, 10),
      audioPath: '',
      durationMs: 60000,
      transcript: 'Alice: ship the beta Friday.',
      minutes: minutes,
      actionItems: items,
    );

ModelManager _ready() => ModelManager(
      downloader: FakeModelDownloader(installed: {
        ModelCatalog.parakeetStt.id,
        ModelCatalog.llama1b.id,
      }),
    )..markAllReadyForTest();

Future<void> _pump(WidgetTester tester,
    {required Meeting meeting,
    required MeetingRepository repo,
    FakeAiEngine? engine,
    ModelManager? manager}) async {
  await tester.pumpWidget(MaterialApp(
    home: TranscriptScreen(
      meeting: meeting,
      repository: repo,
      ai: AiService(engine: engine ?? FakeAiEngine()),
      modelManager: manager ?? _ready(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on Overview with Overview + Transcript tabs',
      (tester) async {
    final m = _meeting(minutes: '### Summary\nAll good.');
    await _pump(tester, meeting: m, repo: FakeMeetingRepository([m]));

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Transcript'), findsOneWidget);
    // Overview is the default tab: cached minutes are visible.
    expect(find.textContaining('All good.'), findsWidgets);
  });

  testWidgets('persistent Ask entry is present', (tester) async {
    final m = _meeting(minutes: '### Summary\nx');
    await _pump(tester, meeting: m, repo: FakeMeetingRepository([m]));
    expect(find.text('Ask about this meeting…'), findsOneWidget);
  });

  testWidgets('overflow menu offers share options and a disabled Export',
      (tester) async {
    final m = _meeting(minutes: '### Summary\nx');
    await _pump(tester, meeting: m, repo: FakeMeetingRepository([m]));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Share minutes'), findsOneWidget);
    expect(find.text('Copy all'), findsOneWidget);
    final export = tester.widget<PopupMenuItem<String>>(
      find.widgetWithText(PopupMenuItem<String>, 'Export (coming soon)'),
    );
    expect(export.enabled, isFalse);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/mobile && flutter test test/screens/transcript_screen_test.dart`
Expected: FAIL — finds `Transcript`/`Minutes` tabs and the old bar, not `Overview`/Ask entry/overflow.

- [ ] **Step 3: Rewrite the screen shell**

Replace `apps/mobile/lib/screens/transcript_screen.dart` with the version below. It reorders tabs (Overview first), removes `_SmartActionBar`, adds the overflow menu + persistent Ask bar, and renders cached content. Auto-generate, checkable items, rename, and real per-section share arrive in Tasks 5–8 (the share handlers here route to a single `meeting_share.dart` helper added in Task 8; for now they share the raw minutes/transcript strings).

```dart
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

  bool _busy = false;
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
```

Keep the existing `_ActionChips`, `_RevealFade`, `_GeneratingView`, `_PulsingSparkle` widgets from the current file (they are reused in Tasks 5–6). **Delete** `_SmartActionBar`, `_SmartButton`, and `_MinutesEmpty` (the old bar and empty state are superseded). Auto-generate methods (`_summarize`, `_actionItems`) are removed here and reintroduced as one pass in Task 5.

- [ ] **Step 4: Run the structure test to verify it passes**

Run: `cd apps/mobile && flutter test test/screens/transcript_screen_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Analyze**

Run: `cd apps/mobile && flutter analyze lib/screens/transcript_screen.dart`
Expected: No issues (no unused `_GeneratingView` warning yet — it's referenced in Task 5; if analyze flags it as unused, add `// ignore: unused_element` temporarily and remove it in Task 5, OR sequence Task 5 immediately after without committing analyze-clean here — prefer committing and removing the ignore in Task 5).

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/screens/transcript_screen.dart apps/mobile/test/screens/transcript_screen_test.dart
git commit -m "feat(r6): Overview-first meeting screen — tabs, overflow menu, persistent Ask"
```

---

## Task 5: Auto-generate pass on open (title + minutes + action items)

**Files:**
- Modify: `apps/mobile/lib/screens/transcript_screen.dart`
- Modify: `apps/mobile/test/screens/transcript_screen_test.dart`

**Interfaces:**
- Consumes: `AiService.summarize/actionItems/generateTitle`, `ModelManager.llmReady`, `repository.update`.
- Produces: on Overview open with a transcript and no cached minutes, one guarded pass generates minutes → action items → title (title only if the current title matches the default shape), each persisted as it lands; states: preparing (LLM not ready), streaming, error+retry. Adds `bool _autoStarted` guard and `bool isDefaultMeetingTitle(String)`.

- [ ] **Step 1: Write the failing auto-generate tests**

Add to `apps/mobile/test/screens/transcript_screen_test.dart` inside `main()`:

```dart
  testWidgets('auto-generates minutes + items + title on open, once',
      (tester) async {
    final m = _meeting(); // no minutes
    final repo = FakeMeetingRepository([m]);
    final engine = FakeAiEngine(
      minutes: '### Summary\nGenerated once.',
      items: const ['Ship it'],
      titleText: 'Beta Launch Sync',
    );
    await _pump(tester, meeting: m, repo: repo, engine: engine);

    expect(find.textContaining('Generated once.'), findsWidgets);
    expect(find.text('Ship it'), findsOneWidget);

    final saved = await repo.byId(1);
    expect(saved?.minutes, contains('Generated once.'));
    expect(saved?.actionItems.map((a) => a.text), ['Ship it']);
    // Default title was auto-upgraded.
    expect(saved?.title, 'Beta Launch Sync');
  });

  testWidgets('does not auto-run when minutes already cached', (tester) async {
    final m = _meeting(minutes: '### Summary\nCached.');
    final repo = FakeMeetingRepository([m]);
    final engine = _CountingAiEngine();
    await _pump(tester, meeting: m, repo: repo, engine: engine);

    expect(engine.summarizeCalls, 0);
  });

  testWidgets('shows Preparing AI hold when LLM not ready', (tester) async {
    final m = _meeting();
    await _pump(
      tester,
      meeting: m,
      repo: FakeMeetingRepository([m]),
      manager: ModelManager(downloader: FakeModelDownloader()), // not ready
    );
    expect(find.textContaining('Preparing on-device AI'), findsOneWidget);
  });
```

Add this counting fake at the bottom of the test file (below `main`):

```dart
class _CountingAiEngine extends FakeAiEngine {
  int summarizeCalls = 0;
  @override
  Future<String> summarize(String transcript,
      {String? userInstructions,
      void Function(String partial)? onToken,
      void Function(double)? onProgress}) async {
    summarizeCalls++;
    return super.summarize(transcript,
        userInstructions: userInstructions, onToken: onToken, onProgress: onProgress);
  }
}
```

(Ensure `FakeAiEngine`'s fields are non-private so it can be subclassed — they already are.)

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/mobile && flutter test test/screens/transcript_screen_test.dart --name auto`
Expected: FAIL — no generation happens; placeholder "No summary yet." shown.

- [ ] **Step 3: Add the default-title helper**

At the top level of `transcript_screen.dart` (above the class), add:

```dart
/// Matches the placeholder title from record_screen._defaultTitle()
/// ("Meeting D/M HH:MM"). Auto-title only overwrites titles of this shape.
final _defaultTitlePattern =
    RegExp(r'^Meeting \d{1,2}/\d{1,2} \d{2}:\d{2}$');

bool isDefaultMeetingTitle(String title) =>
    _defaultTitlePattern.hasMatch(title.trim());
```

- [ ] **Step 4: Add the auto-generate pass + guard + trigger**

In `_TranscriptScreenState`, add the guard field:
```dart
  bool _autoStarted = false;
```

Add the pass method:
```dart
  Future<void> _generateOverview() async {
    if (_busy || _transcript.isEmpty) return;
    setState(() {
      _busy = true;
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
```

- [ ] **Step 5: Wire the trigger + busy/preparing/regenerate UI into `_overviewTab`**

Replace `_overviewTab` with:
```dart
  Widget _overviewTab(ColorScheme scheme) {
    _maybeAutoGenerate();

    if (_busy) {
      return _GeneratingView(
          label: _busyLabel, progress: _progress, streaming: _streaming);
    }

    final hasItems = _meeting.actionItems.isNotEmpty;
    if (!_hasMinutes && !hasItems) {
      // Nothing cached and not generating: either the model is still preparing
      // or there is no transcript to work from.
      final preparing = _transcript.isNotEmpty && !_manager.llmReady;
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
```

Note: `_maybeAutoGenerate` runs from `_overviewTab`, which is rebuilt by the `ListenableBuilder` on `_manager` — so when `llmReady` flips true, the tab rebuilds and the pass fires. The `_autoStarted` guard keeps it single-shot.

- [ ] **Step 6: Run the auto-generate tests to verify they pass**

Run: `cd apps/mobile && flutter test test/screens/transcript_screen_test.dart`
Expected: PASS (all — structure + auto-generate).

- [ ] **Step 7: Analyze + commit**

Run: `cd apps/mobile && flutter analyze lib/screens/transcript_screen.dart`
Expected: No issues (`_GeneratingView` is now referenced; remove any temporary `ignore` added in Task 4).

```bash
git add apps/mobile/lib/screens/transcript_screen.dart apps/mobile/test/screens/transcript_screen_test.dart
git commit -m "feat(r6): auto-generate minutes+items+title on Overview open (guarded, with preparing/retry states)"
```

---

## Task 6: Checkable, persisted action items

**Files:**
- Modify: `apps/mobile/lib/screens/transcript_screen.dart`
- Modify: `apps/mobile/test/screens/transcript_screen_test.dart`

**Interfaces:**
- Consumes: `_meeting.actionItems` (`List<ActionItem>`), `repository.update`.
- Produces: a `_ActionList` widget replacing `_ActionChips` in the Overview: each item is a checkbox row; toggling persists `done` and moves completed items to the bottom; keeps a staggered entrance.

- [ ] **Step 1: Write the failing checkable test**

Add to `transcript_screen_test.dart`:

```dart
  testWidgets('checking an action item persists done and survives rebuild',
      (tester) async {
    final m = _meeting(
      minutes: '### Summary\nx',
      items: const [ActionItem(text: 'Ship it'), ActionItem(text: 'Email Bob')],
    );
    final repo = FakeMeetingRepository([m]);
    await _pump(tester, meeting: m, repo: repo);

    // Tick the first item.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    final saved = await repo.byId(1);
    final shipIt = saved!.actionItems.firstWhere((a) => a.text == 'Ship it');
    expect(shipIt.done, isTrue);
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/mobile && flutter test test/screens/transcript_screen_test.dart --name checking`
Expected: FAIL — no `Checkbox` in the tree (still chips).

- [ ] **Step 3: Add the toggle handler + `_ActionList`, swap it into the Overview**

In `_TranscriptScreenState`, add:
```dart
  Future<void> _toggleItem(int index, bool done) async {
    final items = List<ActionItem>.of(_meeting.actionItems);
    items[index] = items[index].copyWith(done: done);
    setState(() => _meeting = _meeting.copyWith(actionItems: items));
    await widget.repository.update(_meeting);
  }
```

In `_overviewTab`, replace the `_ActionChips(...)` line with:
```dart
          _ActionList(items: _meeting.actionItems, onToggle: _toggleItem),
```

Add the widget (place it near `_ActionChips`; you may delete `_ActionChips` once no longer referenced):
```dart
/// Checkable action-item list. Completed items sink to the bottom and strike
/// through; the initial reveal is staggered.
class _ActionList extends StatelessWidget {
  const _ActionList({required this.items, required this.onToggle});
  final List<ActionItem> items;
  final Future<void> Function(int index, bool done) onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Preserve original indices (onToggle needs them) while showing
    // undone-first, done-last.
    final order = List<int>.generate(items.length, (i) => i)
      ..sort((a, b) {
        if (items[a].done == items[b].done) return a.compareTo(b);
        return items[a].done ? 1 : -1;
      });

    return Column(
      children: [
        for (var pos = 0; pos < order.length; pos++)
          _AnimatedIn(
            delayMs: 40 * pos,
            key: ValueKey('item-${order[pos]}'),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onToggle(order[pos], !items[order[pos]].done),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Checkbox(
                    value: items[order[pos]].done,
                    onChanged: (v) => onToggle(order[pos], v ?? false),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      items[order[pos]].text,
                      style: TextStyle(
                        color: items[order[pos]].done
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                        decoration: items[order[pos]].done
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}

/// Staggered fade/slide-in wrapper (no controller — safe under pumpAndSettle).
class _AnimatedIn extends StatelessWidget {
  const _AnimatedIn({super.key, required this.child, this.delayMs = 0});
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
```

- [ ] **Step 4: Run the checkable test to verify it passes**

Run: `cd apps/mobile && flutter test test/screens/transcript_screen_test.dart`
Expected: PASS (all).

- [ ] **Step 5: Analyze + commit**

Run: `cd apps/mobile && flutter analyze lib/screens/transcript_screen.dart`
Expected: No issues (remove `_ActionChips` if now unused to avoid an unused-element warning).

```bash
git add apps/mobile/lib/screens/transcript_screen.dart apps/mobile/test/screens/transcript_screen_test.dart
git commit -m "feat(r6): checkable, persisted action items (done sinks to bottom)"
```

---

## Task 7: Inline rename

**Files:**
- Modify: `apps/mobile/lib/screens/transcript_screen.dart`
- Modify: `apps/mobile/test/screens/transcript_screen_test.dart`

**Interfaces:**
- Consumes: `repository.update`, `_meeting.copyWith(title:)`.
- Produces: tapping the app-bar title opens a rename dialog; saving a non-blank title persists it and updates the app bar. Because auto-title only overwrites the default shape (Task 5), a rename is permanent.

- [ ] **Step 1: Write the failing rename test**

Add to `transcript_screen_test.dart`:

```dart
  testWidgets('tapping the title renames the meeting', (tester) async {
    final m = _meeting(minutes: '### Summary\nx');
    final repo = FakeMeetingRepository([m]);
    await _pump(tester, meeting: m, repo: repo);

    await tester.tap(find.text('Product sync'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Renamed Meeting');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Renamed Meeting'), findsOneWidget);
    expect((await repo.byId(1))?.title, 'Renamed Meeting');
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/mobile && flutter test test/screens/transcript_screen_test.dart --name renames`
Expected: FAIL — the title is a plain `Text`, tapping does nothing.

- [ ] **Step 3: Make the title tappable + add the rename dialog**

In `build`, replace the `AppBar`'s `title:` with:
```dart
        title: InkWell(
          onTap: _rename,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(_meeting.title, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 6),
            Icon(Icons.edit_outlined,
                size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ]),
        ),
```

Add the method:
```dart
  Future<void> _rename() async {
    final controller = TextEditingController(text: _meeting.title);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename meeting'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'Meeting title'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    final name = result?.trim();
    if (name == null || name.isEmpty) return;
    setState(() => _meeting = _meeting.copyWith(title: name));
    await widget.repository.update(_meeting);
  }
```

- [ ] **Step 4: Run the rename test to verify it passes**

Run: `cd apps/mobile && flutter test test/screens/transcript_screen_test.dart`
Expected: PASS (all).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/screens/transcript_screen.dart apps/mobile/test/screens/transcript_screen_test.dart
git commit -m "feat(r6): inline rename from the app-bar title"
```

---

## Task 8: Per-section share + copy-all (pure assembly) + wire the menu

**Files:**
- Create: `apps/mobile/lib/meeting_share.dart`
- Create: `apps/mobile/test/meeting_share_test.dart`
- Modify: `apps/mobile/lib/screens/transcript_screen.dart`
- Modify: `apps/mobile/test/screens/transcript_screen_test.dart`

**Interfaces:**
- Produces: pure helpers `String actionItemsAsText(List<ActionItem>)`, `String copyAllText(Meeting)`; the overflow menu gains **Share action items** and routes each entry to the right body. Share/clipboard side-effects are exercised via the pure helpers (the menu test asserts routing through a shared seam).

- [ ] **Step 1: Write the failing assembly tests**

Create `apps/mobile/test/meeting_share_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/meeting_share.dart';
import 'package:privoice_core/privoice_core.dart';

Meeting _m() => Meeting(
      title: 'Q3 Planning',
      createdAt: DateTime(2026, 7, 10),
      audioPath: '',
      durationMs: 0,
      minutes: '### Summary\nShip in Q3.',
      actionItems: const [
        ActionItem(text: 'Draft spec', done: true),
        ActionItem(text: 'Email Bob'),
      ],
    );

void main() {
  test('actionItemsAsText renders a checkbox list', () {
    final text = actionItemsAsText(_m().actionItems);
    expect(text, '- [x] Draft spec\n- [ ] Email Bob');
  });

  test('actionItemsAsText is empty for no items', () {
    expect(actionItemsAsText(const []), '');
  });

  test('copyAllText includes title, minutes, and action items', () {
    final text = copyAllText(_m());
    expect(text, contains('Q3 Planning'));
    expect(text, contains('Ship in Q3.'));
    expect(text, contains('- [ ] Email Bob'));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/mobile && flutter test test/meeting_share_test.dart`
Expected: FAIL — `meeting_share.dart` not found.

- [ ] **Step 3: Create the pure helpers**

Create `apps/mobile/lib/meeting_share.dart`:

```dart
import 'package:privoice_core/privoice_core.dart';

/// Action items as a Markdown-style checklist ("- [x]"/"- [ ]"), or '' if none.
String actionItemsAsText(List<ActionItem> items) => items
    .map((a) => '- [${a.done ? 'x' : ' '}] ${a.text}')
    .join('\n');

/// Everything worth copying: title, minutes, and the action checklist.
String copyAllText(Meeting m) {
  final parts = <String>[m.title];
  final minutes = (m.minutes ?? '').trim();
  if (minutes.isNotEmpty) parts.add(minutes);
  final items = actionItemsAsText(m.actionItems);
  if (items.isNotEmpty) parts.add('Action items\n$items');
  return parts.join('\n\n');
}
```

- [ ] **Step 4: Run the assembly tests to verify they pass**

Run: `cd apps/mobile && flutter test test/meeting_share_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Wire the helpers into the overflow menu + add a menu test**

In `transcript_screen.dart`, add `import '../meeting_share.dart';` and (for clipboard) `import 'package:flutter/services.dart';`. Add a **Share action items** menu item after `share_transcript`:
```dart
              const PopupMenuItem(
                  value: 'share_items', child: Text('Share action items')),
```
Update `_onMenu`:
```dart
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
```

Add a menu-content test to `transcript_screen_test.dart`:
```dart
  testWidgets('menu shows Share action items and Copy all', (tester) async {
    final m = _meeting(
        minutes: '### Summary\nx', items: const [ActionItem(text: 'Ship it')]);
    await _pump(tester, meeting: m, repo: FakeMeetingRepository([m]));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Share action items'), findsOneWidget);
    expect(find.text('Copy all'), findsOneWidget);
  });
```

- [ ] **Step 6: Run the app tests to verify they pass**

Run: `cd apps/mobile && flutter test test/screens/transcript_screen_test.dart test/meeting_share_test.dart`
Expected: PASS (all).

- [ ] **Step 7: Full suite + analyze + privacy gate**

Run: `melos run analyze`
Expected: clean.
Run: `melos run test`
Expected: PASS across all packages, including `apps/mobile/test/privacy_gate_test.dart` (zero-network).

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/lib/meeting_share.dart apps/mobile/test/meeting_share_test.dart \
  apps/mobile/lib/screens/transcript_screen.dart apps/mobile/test/screens/transcript_screen_test.dart
git commit -m "feat(r6): per-section share + copy-all"
```

---

## Task 9: Build APK, push to device, update STATUS.md

**Files:**
- Modify: `STATUS.md`

**Interfaces:** none (integration + docs).

- [ ] **Step 1: Debug build**

Run:
```bash
export PATH="/opt/homebrew/bin:$HOME/.pub-cache/bin:/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH"
export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
cd apps/mobile && flutter build apk --debug
```
Expected: `Built build/app/outputs/flutter-apk/app-debug.apk`.

- [ ] **Step 2: Push to the Redmi (per CLAUDE.md device workflow)**

Run (replace `<serial>` from `adb devices`):
```bash
adb -s <serial> push apps/mobile/build/app/outputs/flutter-apk/app-debug.apk /sdcard/Download/privoice.apk
```
Then the user taps `privoice.apk` on the phone to install/update, and verifies on-device:
- Open an existing meeting → Overview auto-generates minutes + items + a real title (no date placeholder); the raw Transcript is the second tab.
- Check an action item → it strikes through and stays checked after leaving and reopening.
- Rename from the app-bar title → persists.
- Overflow → Share minutes / transcript / action items / Copy all work; Export is visibly disabled.
- An older meeting created before this build still shows its action items (v3 migration).

**This step needs the user (device testing handoff).** Report the build path and the checklist; do not claim on-device verification until the user confirms.

- [ ] **Step 3: Update STATUS.md**

In `STATUS.md`: flip **R6** from ⬜ to ✅ (mark *code-complete*; add *verified — Redmi* only after the user confirms Step 2), update "Last updated", move the "Next" pointer to **R7**, and note the schema v3 migration under Known gaps if relevant. Commit:
```bash
git add STATUS.md
git commit -m "docs(status): R6 meeting redesign code-complete"
```

- [ ] **Step 4: Finish the branch**

Use the `superpowers:finishing-a-development-branch` skill to merge `feat/r6-minutes-redesign` into `main` with `--no-ff` once the suite is green (and, per convention, on-device verified).

---

## Self-Review

**Spec coverage:**
- Overview+Transcript structure, Overview default → Task 4. ✅
- Auto-generate on open (title+minutes+actions, guarded, streaming/preparing/retry) → Task 5. ✅
- AI title, folded into the auto-pass, overwrites only the default placeholder → Tasks 3 + 5. ✅
- Checkable persisted action items + model change + migration → Tasks 1, 2, 6. ✅
- Inline rename → Task 7. ✅
- Per-section share + copy-all → Task 8. ✅
- Disabled Export stub → Task 4. ✅
- Persistent Ask entry → Task 4. ✅
- Testing (ActionItem JSON, Meeting serialization + legacy fallback, v2→v3 migration, widget: auto-gen/caching/checkable/preparing/rename/share) → Tasks 1–8. ✅
- Privacy gate stays green → Task 8 Step 7. ✅
- On-device verification + STATUS.md → Task 9. ✅

**Placeholder scan:** No "TBD"/"handle edge cases"/"similar to Task N". Each code step shows full code. The only forward reference is `_GeneratingView` reuse (Task 4 keeps it, Task 5 uses it) — called out explicitly with an analyze note.

**Type consistency:** `ActionItem(text, done)`, `Meeting.actionItems: List<ActionItem>`, `AiEngine.title(String)→Future<String>`, `AiService.generateTitle(String)→Future<String?>`, `cleanTitle(String,{int maxWords})`, `isDefaultMeetingTitle(String)→bool`, `actionItemsAsText(List<ActionItem>)→String`, `copyAllText(Meeting)→String`, `_toggleItem(int,bool)`, `_generateOverview()`, `_maybeAutoGenerate()`, `_regenerate()`, `_ActionList({items,onToggle})` — names/signatures match across tasks. `FakeAiEngine` gains `titleText` + `title()`; the counting subclass overrides `summarize`.
