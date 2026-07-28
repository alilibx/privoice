# Collect Orphaned Meeting Audio — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reclaim meeting audio files that no meeting row references, without breaking the Undo affordance that requires the file to outlive the row.

**Architecture:** One new unit, `MeetingAudioStore` in `packages/core`, exposing a single method `collect(referencedPaths)` that deletes meeting-audio files not in the referenced set. Two call sites: `HomeScreen._delete` after the Undo SnackBar closes (prompt reclamation), and `main()` at startup (backstop for the app-kill case and for files already leaked). No schema change.

**Tech Stack:** Dart/Flutter, `dart:io`, `package:path`, `path_provider`, `flutter_test`. Melos monorepo.

**Spec:** `docs/superpowers/specs/2026-07-28-collect-orphaned-meeting-audio-design.md`

**Branch:** `fix/collect-orphaned-meeting-audio` (already created off `main`)

## Global Constraints

- **The invariant:** an audio file that no meeting row references is garbage. One predicate, one place.
- **Never branch on whether Undo was tapped.** Re-read the rows and collect what is unreferenced. This stays correct if Undo ever becomes reachable another way.
- **`collect` must never delete `privoice.db`.** Meeting audio lives in the *same* directory as the database. Only names matching `^(meeting|imported)_\d+\.wav$` are ever considered.
- **Snapshot the directory listing before deleting**, so a file created mid-sweep cannot be collected.
- **Collection failure must never surface to the user or block launch.** Swallow and log; the next startup retries.
- **`audioPath` may be `''`** (the dev seed at `apps/mobile/lib/main.dart:54`) and may point at a file that no longer exists. Neither may throw.
- Repo conventions: conventional commits; `melos run analyze` must be clean and `melos run test` green before each commit.
- Environment for every command in this plan:
  ```bash
  export PATH="/opt/homebrew/bin:$HOME/.pub-cache/bin:$PATH"
  export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
  ```

## File Structure

| File | Responsibility |
|---|---|
| `packages/core/lib/src/meeting_audio_store.dart` | **Create.** The whole mechanism: directory + filename policy + `collect`. |
| `packages/core/lib/privoice_core.dart` | **Modify.** Export the new unit. |
| `packages/core/test/meeting_audio_store_test.dart` | **Create.** Unit tests against temp dirs, including the never-delete-the-database test. |
| `apps/mobile/lib/screens/home_screen.dart` | **Modify.** Inject the store; collect after the SnackBar closes; hold Undo's future so collection cannot race the re-insert. |
| `apps/mobile/test/screens/home_screen_test.dart` | **Modify.** Two widget tests: Undo keeps the file; SnackBar expiry removes it. |
| `apps/mobile/lib/main.dart` | **Modify.** Startup collection, before `runApp`. |
| `STATUS.md` | **Modify.** Record the new behaviour, the retained limitation, and the merge interaction with `feat/audio-import`. |

---

### Task 1: `MeetingAudioStore`

The core unit. A reviewer could accept this and reject the wiring, or vice versa.

**Files:**
- Create: `packages/core/lib/src/meeting_audio_store.dart`
- Modify: `packages/core/lib/privoice_core.dart`
- Test: `packages/core/test/meeting_audio_store_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `class MeetingAudioStore`
  - `const MeetingAudioStore(Directory directory)`
  - `static Future<MeetingAudioStore> forApp()` — resolves the app documents directory via `path_provider`
  - `static bool isMeetingAudioFileName(String name)`
  - `Future<int> collect(Iterable<String> referencedPaths)` — returns count deleted
  - Exported from `package:privoice_core/privoice_core.dart`

- [ ] **Step 1: Write the failing tests**

Create `packages/core/test/meeting_audio_store_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:privoice_core/privoice_core.dart';

void main() {
  late Directory dir;
  late MeetingAudioStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('meeting_audio_store');
    store = MeetingAudioStore(dir);
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  File touch(String name) =>
      File(p.join(dir.path, name))..writeAsStringSync('x');

  test('deletes unreferenced recording and imported audio', () async {
    final recording = touch('meeting_1000.wav');
    final imported = touch('imported_2000.wav');

    expect(await store.collect(const []), 2);
    expect(recording.existsSync(), isFalse);
    expect(imported.existsSync(), isFalse);
  });

  test('keeps referenced audio and collects only the rest', () async {
    final kept = touch('meeting_1000.wav');
    final orphan = touch('meeting_2000.wav');

    expect(await store.collect([kept.path]), 1);
    expect(kept.existsSync(), isTrue);
    expect(orphan.existsSync(), isFalse);
  });

  test('never deletes the database or any other non-audio file', () async {
    // privoice.db lives in this very directory and no meeting references it.
    // A broader rule than the filename pattern would destroy the user's data.
    final files = [
      touch('privoice.db'),
      touch('privoice.db-wal'),
      touch('privoice.db-journal'),
      touch('notes.txt'),
      touch('meeting_abc.wav'), // no digits
      touch('my_meeting_1.wav'), // wrong prefix
      touch('meeting_1.mp3'), // wrong extension
    ];

    expect(await store.collect(const []), 0);
    for (final f in files) {
      expect(f.existsSync(), isTrue,
          reason: '${p.basename(f.path)} must never be collected');
    }
  });

  test('tolerates an empty audioPath among the referenced paths', () async {
    // The dev seed inserts a Meeting with audioPath: ''.
    final orphan = touch('meeting_1000.wav');
    expect(await store.collect(const ['']), 1);
    expect(orphan.existsSync(), isFalse);
  });

  test('tolerates a referenced path whose file is already gone', () async {
    final kept = touch('meeting_1000.wav');
    final missing = p.join(dir.path, 'meeting_9999.wav');

    expect(await store.collect([kept.path, missing]), 0);
    expect(kept.existsSync(), isTrue);
  });

  test('returns zero when the directory does not exist', () async {
    await dir.delete(recursive: true);
    expect(await store.collect(const []), 0);
  });

  test('protects a referenced file even if its stored path is stale', () async {
    // audioPath is persisted absolute, but a container path can differ from the
    // one recorded at write time. Matching on the file name means a stale
    // directory prefix still protects the file: the safe direction is to keep.
    final kept = touch('meeting_1000.wav');
    expect(await store.collect(const ['/old/container/meeting_1000.wav']), 0);
    expect(kept.existsSync(), isTrue);
  });

  test('isMeetingAudioFileName recognises exactly the writers we have', () {
    expect(MeetingAudioStore.isMeetingAudioFileName('meeting_1.wav'), isTrue);
    expect(MeetingAudioStore.isMeetingAudioFileName('imported_1.wav'), isTrue);
    expect(MeetingAudioStore.isMeetingAudioFileName('privoice.db'), isFalse);
    expect(MeetingAudioStore.isMeetingAudioFileName('meeting_.wav'), isFalse);
    expect(MeetingAudioStore.isMeetingAudioFileName('xmeeting_1.wav'), isFalse);
  });

  // Why MeetingRepository.delete is deliberately NOT changed to delete the file:
  // Home's Undo re-inserts the meeting, so the file must outlive the row. Making
  // delete() remove the file is the obvious fix and it breaks Undo — restoring a
  // meeting whose audio is already gone. Collection is therefore keyed on "is
  // anything still referencing this file", never on the delete call. If you are
  // here because you were about to move deletion into the repository: don't.
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd packages/core && flutter test test/meeting_audio_store_test.dart
```

Expected: FAIL at compile — `Error: 'MeetingAudioStore' isn't a type.` / undefined name. Do not proceed until you have seen it fail for this reason.

- [ ] **Step 3: Write the implementation**

Create `packages/core/lib/src/meeting_audio_store.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Deletes meeting audio files that no meeting row references.
///
/// The invariant is single: **an audio file no meeting references is garbage.**
/// Deleting a meeting cannot delete its file directly, because Home's Undo
/// re-inserts the meeting and needs the file to outlive the row — so file
/// lifetime is tied to whether anything still references the file, never to the
/// delete call. Prompt reclamation (after the Undo window closes) and the
/// startup backstop are both call sites of [collect].
///
/// **Precondition: only call [collect] when no recording or import is in
/// flight.** `ImportScreen` writes its WAV and inserts the `Meeting` row only
/// after transcription finishes — minutes later for a long file — so an
/// in-progress import is legitimately unreferenced and would be collected. That
/// is safe today only because both capture screens are pushed above Home in the
/// navigator, and the startup pass runs before any capture is possible. If that
/// ever stops holding (a periodic sweep, a background task, a "reclaim space"
/// button), make in-flight files unmistakable — write to a `.part` name and
/// rename on commit, or move meeting audio into its own subdirectory — rather
/// than weakening the sweep.
class MeetingAudioStore {
  const MeetingAudioStore(this.directory);

  /// The directory recordings and imports are actually written to:
  /// `AppAudioRecorder.start` and `ImportScreen._run` both use app documents.
  static Future<MeetingAudioStore> forApp() async =>
      MeetingAudioStore(await getApplicationDocumentsDirectory());

  final Directory directory;

  /// Names that meeting-audio writers produce. **Must stay in sync with every
  /// writer:** `RecordingConfig.fileName` (`meeting_<ms>.wav`) and
  /// `ImportScreen._run` (`imported_<ms>.wav`). A new naming scheme that is not
  /// added here leaks silently.
  ///
  /// This pattern is also the safety boundary: `privoice.db` and its journal
  /// siblings live in the same directory and are referenced by no meeting, so a
  /// broader rule than this would delete the user's database.
  static final RegExp _audioFileName = RegExp(r'^(meeting|imported)_\d+\.wav$');

  static bool isMeetingAudioFileName(String name) =>
      _audioFileName.hasMatch(name);

  /// Deletes meeting audio in [directory] whose file name is not among
  /// [referencedPaths]. Returns how many files were deleted.
  ///
  /// Matching is by file name, not by full path: `audioPath` is persisted
  /// absolute, and a stale directory prefix should still protect the file. The
  /// asymmetry is deliberate — the failure mode of name matching is keeping a
  /// file we could have deleted, never deleting one we needed.
  Future<int> collect(Iterable<String> referencedPaths) async {
    if (!await directory.exists()) return 0;

    final keep = referencedPaths
        .where((path) => path.isNotEmpty)
        .map(p.basename)
        .toSet();

    // Snapshot the listing BEFORE deleting anything: a file created after this
    // completes cannot be collected by this pass, which closes the race with a
    // capture that starts mid-sweep.
    final candidates = await directory
        .list(followLinks: false)
        .where((entity) => entity is File)
        .map((entity) => entity.path)
        .where((path) => isMeetingAudioFileName(p.basename(path)))
        .toList();

    var deleted = 0;
    for (final path in candidates) {
      if (keep.contains(p.basename(path))) continue;
      try {
        await File(path).delete();
        deleted++;
      } on FileSystemException {
        // Vanished between the snapshot and the delete, or not ours to remove.
        // Leaving it is harmless — the next collect retries.
      }
    }
    return deleted;
  }
}
```

- [ ] **Step 4: Export it**

In `packages/core/lib/privoice_core.dart`, add the export so the line order stays alphabetical:

```dart
export 'src/action_item.dart';
export 'src/meeting.dart';
export 'src/meeting_audio_store.dart';
export 'src/meeting_repository.dart';
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd packages/core && flutter test test/meeting_audio_store_test.dart
```

Expected: PASS, 8 tests.

- [ ] **Step 6: Verify the safety test is load-bearing**

Temporarily broaden the pattern to `RegExp(r'.*')`, re-run, and confirm the
`never deletes the database` test FAILS. Then restore the real pattern and
confirm it passes again. A safety test that cannot fail is not protecting
anything.

```bash
cd packages/core && flutter test test/meeting_audio_store_test.dart
```

- [ ] **Step 7: Run the full gate**

```bash
melos run analyze && melos run test
```

Expected: analyze clean, all packages green.

- [ ] **Step 8: Commit**

Use a heredoc — the commit body mentions a regex, and `-m` with backslashes in
double quotes will mangle it.

```bash
git add packages/core/lib/src/meeting_audio_store.dart \
        packages/core/lib/privoice_core.dart \
        packages/core/test/meeting_audio_store_test.dart
git commit -F - <<'EOF'
feat(core): MeetingAudioStore collects unreferenced meeting audio

Deleting a meeting removes only the row: Home's Undo re-inserts the meeting and
needs the file to outlive it, so file lifetime cannot be tied to the delete call.
This inverts it into one invariant — an audio file no meeting references is
garbage — so collect() serves both the undo-window-expired and app-killed cases.

The safety boundary is the filename pattern. Meeting audio lives in the same
directory as privoice.db, so a broader rule would delete the database on first
run; only names matching ^(meeting|imported)_\d+\.wav$ are ever considered, and
the test asserting the database survives was mutation-verified by broadening the
pattern to match everything.

Matching is by file name rather than full path so a stale absolute prefix still
protects a file — the failure mode is keeping a collectable file, never deleting
a needed one.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

### Task 2: Collect after the Undo window closes

**Files:**
- Modify: `apps/mobile/lib/screens/home_screen.dart` (constructor ~14-28, `_delete` at 95-111)
- Test: `apps/mobile/test/screens/home_screen_test.dart`

**Interfaces:**
- Consumes: `MeetingAudioStore` and `MeetingAudioStore.collect` from Task 1.
- Produces: `HomeScreen` gains an optional `MeetingAudioStore? audioStore` constructor parameter (defaults to `MeetingAudioStore.forApp()` at use time). Task 3 does not depend on this.

**Why the Undo future is held:** `SnackBarAction.onPressed` starts an *async* re-insert. `closed` completes when the dismiss animation ends, which can be before that insert lands — so collecting straight after `closed` could read the rows too early and delete the file the user just restored. Holding the future and awaiting it removes the race while keeping the "ask the rows, not the reason" property.

- [ ] **Step 1: Write the failing tests**

In `apps/mobile/test/screens/home_screen_test.dart`, add these imports at the top (keep the existing ones):

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
```

Then add this helper above `void main()`:

```dart
/// `testWidgets` runs in a fake-async zone where real `dart:io` work cannot
/// complete, so pumping alone never lets a file delete land. Alternating
/// `runAsync` (real event loop) with `pump` (render) is what makes it finish.
/// Fails on exhaustion rather than returning quietly.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int tries = 100,
  String? reason,
}) async {
  for (var i = 0; i < tries; i++) {
    if (ready()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump();
  }
  if (!ready()) {
    fail('pumpUntil gave up after $tries frames'
        '${reason == null ? '' : ': $reason'}');
  }
}
```

And add these two tests inside `main()`, at the end:

```dart
  group('deleting a meeting collects its audio', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('home_audio');
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    /// A meeting whose audio is a real file in [dir].
    (Meeting, File) seeded() {
      final file = File(p.join(dir.path, 'meeting_1000.wav'))
        ..writeAsStringSync('x');
      return (
        Meeting(
          title: 'Standup',
          createdAt: DateTime(2026, 7, 10, 9),
          audioPath: file.path,
          durationMs: 60000,
          transcript: 'daily sync',
        ),
        file,
      );
    }

    Widget hostWithStore(MeetingRepository repo) => MaterialApp(
          home: HomeScreen(
            repository: repo,
            ai: AiService(),
            themeMode: ValueNotifier(ThemeMode.system),
            modelManager: readyManager(),
            audioStore: MeetingAudioStore(dir),
          ),
        );

    testWidgets('Undo keeps the audio file', (tester) async {
      final (meeting, file) = seeded();
      await tester.pumpWidget(hostWithStore(FakeMeetingRepository([meeting])));
      await tester.pumpAndSettle();

      await tester.fling(
          find.text('Standup'), const Offset(-500, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      // Let the re-insert land, the SnackBar close, and collection run.
      await pumpUntil(tester, () => find.text('Undo').evaluate().isEmpty,
          reason: 'the SnackBar never closed');
      await pumpUntil(tester, () => find.text('Standup').evaluate().isNotEmpty,
          reason: 'the meeting was never restored');

      expect(file.existsSync(), isTrue,
          reason: 'Undo restored the meeting, so its audio must survive');
    });

    testWidgets('letting the SnackBar expire collects the audio file',
        (tester) async {
      final (meeting, file) = seeded();
      await tester.pumpWidget(hostWithStore(FakeMeetingRepository([meeting])));
      await tester.pumpAndSettle();

      await tester.fling(
          find.text('Standup'), const Offset(-500, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsOneWidget);

      // Default SnackBar duration is 4s; run past it, then let collection land.
      await tester.pump(const Duration(seconds: 5));
      await pumpUntil(tester, () => !file.existsSync(),
          reason: 'the orphaned audio was never collected');

      expect(file.existsSync(), isFalse);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd apps/mobile && flutter test test/screens/home_screen_test.dart
```

Expected: FAIL at compile — `No named parameter with the name 'audioStore'`.

- [ ] **Step 3: Add the constructor parameter**

In `apps/mobile/lib/screens/home_screen.dart`, extend the constructor and fields:

```dart
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
```

- [ ] **Step 4: Rewrite `_delete` and add the collection helper**

Replace `_delete` (currently lines 95-111) with:

```dart
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
    await _collectAudio();
  }

  Future<void> _undoDelete(Meeting m) async {
    await widget.repository.insert(m);
    await _load();
  }

  /// Reclaims audio no meeting references. Failing to reclaim disk must never
  /// surface over a successful delete — the startup pass retries.
  Future<void> _collectAudio() async {
    try {
      final store = widget.audioStore ?? await MeetingAudioStore.forApp();
      final meetings = await widget.repository.all();
      await store.collect(meetings.map((m) => m.audioPath));
    } catch (e) {
      // Swallowed, but not silently — a bare `catch (_) {}` here would hide a
      // real bug forever, and this path is invisible to the user by design.
      debugPrint('Audio collection after delete skipped: $e');
    }
  }
```

`MeetingAudioStore` comes from the existing `package:privoice_core/privoice_core.dart` import — no new import needed.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd apps/mobile && flutter test test/screens/home_screen_test.dart
```

Expected: PASS, 10 tests (8 existing + 2 new).

- [ ] **Step 6: Verify the Undo test is load-bearing**

Temporarily delete the `await undo;` line, re-run, and confirm the
`Undo keeps the audio file` test FAILS (it should collect the restored file).
This proves the race is real and the fix is what closes it. Restore the line and
confirm green again.

If it does NOT fail, the race is not reproducible under the test's timing —
record that in the commit message honestly rather than claiming the test proves
it, and keep `await undo` anyway on correctness grounds.

- [ ] **Step 7: Run the full gate**

```bash
melos run analyze && melos run test
```

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/lib/screens/home_screen.dart \
        apps/mobile/test/screens/home_screen_test.dart
git commit -F - <<'EOF'
feat(mobile): reclaim meeting audio when the undo window closes

After the delete SnackBar closes, Home collects audio no meeting references. It
does not check whether Undo was tapped: it re-reads the rows and collects what is
unreferenced, so a restored meeting keeps its file by construction.

Undo's re-insert is async and can outlive the dismiss animation, so its future is
held and awaited before collecting — otherwise the rows are read too early and
the file the user just restored gets deleted.

Collection failure is swallowed: leaving a file for the startup pass to retry
beats an error surfacing over a successful delete.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

### Task 3: Startup backstop and STATUS.md

**Files:**
- Modify: `apps/mobile/lib/main.dart` (after `_maybeSeed`, before `runApp`, ~line 36-39; new helper below `_maybeSeed`)
- Modify: `STATUS.md`

**Interfaces:**
- Consumes: `MeetingAudioStore.forApp` and `collect` from Task 1.
- Produces: nothing later depends on this.

**Why startup:** it is the only pass that runs when no capture can possibly be in flight, and it covers both the app-killed-during-undo case and files leaked before collection existed — so existing installs self-heal on next launch with no migration code.

- [ ] **Step 1: Add the startup call**

In `apps/mobile/lib/main.dart`, inside `main()`, add the call after `_maybeSeed` and `_maybeAiSelfTest` and before `runApp`:

```dart
  await _maybeSeed(repository);
  await _maybeAiSelfTest();
  await _collectOrphanedAudio(repository);
  runApp(PrivoiceApp(repository: repository, ai: AiService(), themeMode: themeMode));
```

- [ ] **Step 2: Add the helper**

Add below `main()` in `apps/mobile/lib/main.dart`:

```dart
/// Reclaims meeting audio no row references. This is the backstop for a delete
/// whose undo window was cut short by the process being killed, and it also
/// collects files leaked before collection existed, so existing installs
/// self-heal on the next launch.
///
/// Runs here because startup is the one moment no recording or import can be in
/// flight — [MeetingAudioStore.collect]'s precondition. Never blocks launch:
/// reclaiming disk matters less than starting, and the next launch retries.
Future<void> _collectOrphanedAudio(MeetingRepository repository) async {
  try {
    final store = await MeetingAudioStore.forApp();
    final meetings = await repository.all();
    final collected = await store.collect(meetings.map((m) => m.audioPath));
    if (collected > 0) {
      debugPrint('Collected $collected orphaned meeting audio file(s).');
    }
  } catch (e) {
    debugPrint('Orphaned-audio collection skipped: $e');
  }
}
```

`debugPrint` comes from `package:flutter/material.dart`, already imported. `MeetingAudioStore` comes from the existing `privoice_core` import.

- [ ] **Step 3: Verify it compiles and the gate is green**

```bash
melos run analyze && melos run test
```

Expected: analyze clean, all packages green. There is no unit test for `main()` itself — it is untestable wiring; Task 1 covers the behaviour and this step is verified by inspection plus the build.

- [ ] **Step 4: Verify on the iOS simulator**

The startup pass is the one piece no test covers, so exercise it for real.

```bash
cd apps/mobile && flutter build ios --debug --simulator
```

Then, with the app installed on a booted simulator:

1. Find the container: `xcrun simctl get_app_container booted com.privoice.mobile.beta data`
2. Create a decoy orphan and a decoy database in `Documents/`:
   ```bash
   C=$(xcrun simctl get_app_container booted com.privoice.mobile.beta data)
   printf 'x' > "$C/Documents/meeting_1.wav"
   ls -l "$C/Documents/"
   ```
3. Relaunch the app.
4. Confirm `meeting_1.wav` is gone **and** `privoice.db` is still present with the app's meetings intact.

Record the result in the commit message. If `privoice.db` disappears, stop — that is the failure mode this whole design exists to prevent.

- [ ] **Step 5: Update STATUS.md**

Under `## Known gaps / tech debt` (heading at line 146), add:

```markdown
- **Meeting audio is collected, but only at two moments (by design).** Deleting a meeting removes the row immediately; the audio file is reclaimed by `MeetingAudioStore.collect` when the undo window closes, and again at startup as a backstop for the app being killed mid-window. `collect` deliberately only considers `^(meeting|imported)_\d+\.wav$`, because meeting audio shares a directory with `privoice.db` and a broader rule would delete the database — **any new audio naming scheme must be added to that pattern or it will leak silently.** It also carries a precondition: it must not run while a recording or import is in flight, since `ImportScreen` writes its WAV minutes before inserting the row. Safe today because both capture screens sit above Home in the navigator. If a periodic sweep or a "reclaim space" button is ever added, make in-flight files unmistakable (a `.part` name renamed on commit, or a dedicated audio subdirectory) rather than weakening the sweep. The subdirectory is the cleaner long-term shape but needs a data migration, since existing `audioPath` values point at the documents root.
```

Under `**Working ✅**` in the *Feature checklist* section, add to the persistence line group:

```markdown
- **Meeting audio is reclaimed on delete** (undo-safe: the file outlives the row until the undo window closes)
```

Update `**Last updated:**` at the top to `2026-07-28`.

- [ ] **Step 6: Note the merge interaction with `feat/audio-import`**

`feat/audio-import` adds a Known-gaps bullet beginning **"Deleting a meeting never deletes its audio file (pre-existing, newly expensive)."** That bullet does not exist on `main` — it was added on that branch. Whichever branch merges second must **delete that bullet**, because this task resolves it.

Add this line immediately after the bullet written in Step 5 so the next person merging sees it:

```markdown
  <!-- MERGE NOTE: feat/audio-import adds a "Deleting a meeting never deletes its audio file" gap bullet. This task resolves it — delete that bullet when the branches merge. -->
```

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/main.dart STATUS.md
git commit -F - <<'EOF'
feat(mobile): collect orphaned meeting audio at startup

The backstop for the case Home cannot cover: if the process is killed during the
undo window, the prompt reclamation never runs. Startup is also the only moment
no capture can be in flight, which is collect()'s precondition, and it makes
existing installs self-heal — files leaked before collection existed are
reclaimed on the next launch with no migration code.

Swallowed and logged rather than awaited fatally: reclaiming disk matters less
than launching.

STATUS.md records the retained limitations — the filename pattern that any new
writer must be added to, and the in-flight precondition with the right fix if it
ever stops holding — plus a merge note, since feat/audio-import adds a gap bullet
this resolves.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

## Verification checklist

Run before declaring done:

- [ ] `melos run analyze` clean
- [ ] `melos run test` green, all 6 packages
- [ ] Task 1 Step 6 done: the never-delete-the-database test was seen to fail with a broadened pattern
- [ ] Task 2 Step 6 done: the `await undo` line was seen to be load-bearing, or its non-reproducibility recorded honestly
- [ ] Task 3 Step 4 done: on-simulator relaunch collected a decoy orphan and left `privoice.db` and existing meetings intact
- [ ] STATUS.md `Last updated` bumped, gap bullet + merge note present
