# Collect orphaned meeting audio — design

**Date:** 2026-07-28
**Status:** approved, ready for implementation plan
**Branch:** `fix/collect-orphaned-meeting-audio` (off `main`)

## Problem

`SqfliteMeetingRepository.delete` (`packages/core/lib/src/meeting_repository.dart:118`) removes only
the DB row. The audio file at `Meeting.audioPath` stays on disk permanently, and nothing ever
collects it.

The file is kept deliberately: `HomeScreen._delete`
(`apps/mobile/lib/screens/home_screen.dart`) shows an **Undo** SnackBar whose action re-inserts the
same `Meeting`, so the file has to outlive the row deletion. But it outlives it forever.

This was tolerable when every meeting was a short recording. The audio-import feature
(`feat/audio-import`) keeps the converted 16 kHz mono WAV as the meeting's `audioPath` at
**~115 MB per hour of audio**, so importing and discarding a few meetings leaks hundreds of MB with
no way for the user to reclaim it short of clearing app data.

## The load-bearing decision

The obvious fix — make `delete()` also delete the file — is wrong: it breaks Undo, which is exactly
why the file survives today. File lifetime cannot be tied to the delete *call*.

Instead the design tightens a single invariant:

> **An audio file that no meeting row references is garbage.**

One predicate, enforced in one place. Both failure cases (undo window expired; app killed during the
undo window) become call sites of the same operation rather than two separate mechanisms.

A consequence worth stating plainly: the implementation **never asks whether Undo was tapped.** After
the SnackBar closes it re-reads the rows and collects whatever is unreferenced. If Undo was used, the
path is referenced again and the file stays — correct by construction, and it stays correct if Undo
ever becomes reachable by another route (a "Recently deleted" view, an undo gesture, a test).

## Decision: ephemeral undo, no schema change

Undo stays tied to the SnackBar, as today. Rejected alternative: a `deleted_at` soft-delete column
(schema v5) that would let Undo survive a relaunch. It costs a migration and forces every read query
to filter `deleted_at IS NULL`, and buys nothing users can see — the SnackBar already vanishes on
restart, so there is no durable-undo affordance to preserve.

## Architecture

### New unit: `MeetingAudioStore` (`packages/core`)

Lives beside the repository in `packages/core`, not in `packages/audio`: the policy is defined by
`Meeting` rows, and putting it in `packages/audio` would force an `audio → core` dependency that does
not otherwise exist.

Takes its directory as a constructor argument so tests use a temp dir and never touch
`path_provider`. This matches the injection convention used elsewhere in the codebase.

Its surface is one predicate in two scopes (**corrected after review** — see §3):

```dart
/// Sweeps the directory. Deletes every meeting audio file no meeting
/// references. Returns how many files were removed. Quiescent moments only.
Future<int> collect(Iterable<String> referencedPaths)

/// Deletes this one file if no meeting references it. Safe at any moment.
Future<bool> collectOne(String path, Iterable<String> referencedPaths)
```

Both ask the same question of a file — *is its name one a meeting-audio writer produces, and is that
name unreferenced?* — through one private predicate. They differ only in how many files they ask it
about. The "one predicate, one place" property is the point of the design; the two scopes are a
blast-radius choice, not a second mechanism.

### Call sites

| When | Scope | Purpose |
|---|---|---|
| `HomeScreen._delete`, after the SnackBar closes | `collectOne(m.audioPath, …)` | reclaims the file promptly, and *only* that file |
| App startup (`main.dart`), after the repository opens | `collect(…)` | catches the app-kill case, and anything already leaked by past installs |

The startup call is also the migration story: existing users with already-orphaned files get them
reclaimed on the next launch, with no extra code.

In both cases `referencedPaths` is `await repository.audioPaths()` — the live row set, read at the
moment of collection, never a cached list. `audioPaths()` is a projection (`columns: ['audio_path']`)
rather than `all()`: `Meeting.fromRow` decodes a whole transcript and runs a `jsonDecode` per row for
action items, all of it discarded here, and the startup call pays that cost before `runApp`, over the
Android platform channel, on the slowest device we support.

**Startup must not be blocked or broken by collection.** Reclaiming disk is never more important than
launching the app, so the startup call is awaited but wrapped so a failure (permissions, a directory
that does not exist yet on first launch) is swallowed and logged rather than propagated. The same
applies to the `HomeScreen` call site: a failed collection leaves a file behind, which the next
startup retries, and that is strictly better than an error surfacing over a successful delete.

## Safety properties

Each of these gets a test. The first is the one that could destroy user data.

### 1. It must never delete the database

Meeting audio lives in the **same directory as `privoice.db`** — both are in the app documents
directory (`SqfliteMeetingRepository.open` and `AppAudioRecorder.start` both use
`getApplicationDocumentsDirectory()`). A sweep that deleted "every file with no matching row" would
delete the database on first run.

So `collect` only ever considers files matching the names that meeting-audio writers actually
produce:

```
^(meeting|imported)_\d+\.wav$
```

- `meeting_<ms>.wav` — `RecordingConfig.fileName` (`packages/audio/lib/src/recording_config.dart:18`)
- `imported_<ms>.wav` — `ImportScreen._run`, on the `feat/audio-import` branch

**Note:** the `imported_` pattern has no writer on `main` yet — that writer arrives with
`feat/audio-import`. It is included deliberately, because the import feature is the entire motivation
for this fix and the two branches will meet. The pattern list is a single named constant documented as
*must stay in sync with every writer of meeting audio*; adding a third naming scheme without updating
it would silently leak again.

Everything not matching the pattern is invisible to `collect`: `privoice.db`, its journal/WAL
siblings, and anything else the app or OS puts there.

### 2. Snapshot before delete

`collect` lists the directory first, then deletes only from that snapshot. A file created after the
listing cannot be deleted by an in-flight sweep, which closes the obvious race.

### 3. Scope, not a precondition — **corrected after review**

> **What this section originally argued, and why it was wrong.** It claimed a whole-directory sweep
> from `HomeScreen` was safe "because both capture screens (`RecordScreen`, `ImportScreen`) are pushed
> *above* Home, so neither call site can fire mid-capture," and turned that into a documented
> precondition ("only call when no capture or import is in flight"). That is a non-sequitur.
> `ScaffoldMessenger` sits **above** the `Navigator`, so the SnackBar's auto-dismiss timer arms and
> fires regardless of which route is on top, and `_HomeScreenState` stays mounted underneath and runs
> `_delete`'s pending continuation. Pushing a route does not suspend it. The whole-branch review
> reproduced two data-loss bugs from this, both fixed by the scope split below. The original argument
> is recorded here rather than quietly deleted, because "a route is on top" is an attractive and wrong
> reason to believe code is not running.

Meeting audio is **legitimately unreferenced while it is being captured.** `AppAudioRecorder.start`
creates `meeting_<ms>.wav` immediately and `RecordScreen` inserts the row only after transcription
finishes; `ImportScreen` does the same, minutes later for a long file. It is **not** only
`ImportScreen` — a plain recording has exactly the same window.

So a whole-directory sweep is only safe at a moment when nothing can be writing meeting audio, and
there are two distinct bad moments to protect against, both live at Home:

1. **A capture in flight.** Delete a meeting; start recording inside the undo window; when the window
   closes, a sweep deletes the in-flight WAV. Transcription then fails and the recording is lost.
2. **A second delete's undo window.** `ScaffoldMessenger.showSnackBar` queues FIFO. Delete A then B
   in quick succession: both rows are already gone, so when A's window closes a sweep deletes B's
   audio while B's **Undo is still on screen**. Tapping Undo restores a row pointing at a deleted
   file. `await undo` is per-invocation; a sweep is global.

The fix is scope, and it holds by construction rather than by a precondition anyone has to remember:

- **App startup owns the sweep.** Nothing can be recording or importing before `runApp`, so that
  moment genuinely is quiescent — the one place `collect` belongs.
- **Home deletes exactly one named file** with `collectOne(m.audioPath, …)`. An in-flight recording is
  a different path, so it can never be the target; meeting B's file is a different path, so A's
  continuation can never touch it. Both bugs die by construction, not by timing.

Each of the two bugs has a regression test in `home_screen_test.dart`; both were confirmed to fail
against the pre-fix code.

If a whole-directory sweep is ever wanted at a non-quiescent moment — a periodic sweep, a background
task, a settings-screen "reclaim space" button — the correct fix is to make in-flight files
unmistakable rather than to weaken the predicate: write to a `.part` suffix and rename on commit, or
move meeting audio into a dedicated subdirectory.

### 4. A bounded undo window, and what that costs

The Undo SnackBar carries an action, and Flutter defaults `persist` to `action != null`
(`snack_bar.dart`), while `ScaffoldMessengerState.build` makes the auto-dismiss timer `return` without
hiding when `persist` is set. Left at the default the SnackBar never auto-closes, so the undo window
never closes and prompt reclamation never runs. Hence `persist: false`.

`persist` is also how Flutter now implements the documented "a SnackBar with an action does not time
out under TalkBack/VoiceOver" exemption, so opting out of persist opts out of that too: a
screen-reader user gets a bounded — and, under `accessibleNavigation`, unanimated — window to
double-tap Undo on a destructive action. The concession is an explicit `duration: 10s` instead of the
4s default: long enough to hear the announcement and act, short enough that the file is reclaimed
promptly. Recorded as an accepted cost, not an oversight.

### Also handled

- `audioPath` can be `''` (the dev seed at `apps/mobile/lib/main.dart:54`). An empty referenced path
  must not match any file, and must not throw.
- A referenced path whose file is already gone must not throw.
- Deleting a file that vanished between the snapshot and the delete must not throw.

## Deliberately out of scope

- **No schema change** (decided above).
- **Not moving audio to a dedicated subdirectory.** It would make sweeping trivially safe, but
  existing installs have `audioPath` values pointing at the documents root, so it needs a data
  migration. Pattern-matching is the lower-risk fix. Logged as a follow-up.
- **Not deleting audio after transcription succeeds.** This would reclaim far more — nothing reads
  the file today — but "Audio playback" is a listed Todo in STATUS.md, so the intent to keep it is
  already recorded. Changing that is a product decision, not a bug fix.
- **No UI.** No "reclaim space" button, no toast reporting bytes freed. `collect` returns a count for
  tests and future logging, and that is all.

## Testing

`MeetingAudioStore` is pure `dart:io` against temp directories, so there is nothing to mock:

- deletes an unreferenced `meeting_*.wav` and an unreferenced `imported_*.wav`
- keeps a referenced file
- **leaves `privoice.db` untouched** even though no row references it
- leaves other non-matching files untouched (e.g. `notes.txt`, `privoice.db-wal`)
- tolerates `''` among the referenced paths
- tolerates a referenced path whose file is missing
- returns the number actually deleted

`collectOne` gets the same treatment, plus the property the scope split exists for: **it never touches
any file other than the one named** (an in-flight capture, another pending delete's audio and
`privoice.db` all survive a `collectOne` aimed at a fourth file), and a path outside the directory
resolves inside it rather than deleting somewhere the store does not own.

`SqfliteMeetingRepository.audioPaths()` gets tests for the projection itself: one entry per row
including `''`, and nothing for a deleted row.

`HomeScreen` widget tests, with the store injected:

- delete → tap **Undo** → the file still exists
- delete → let the SnackBar close → the file is gone
- **delete A, then delete B before A's window closes → B's file still exists** (finding 2)
- **delete A, then a capture creates an unreferenced `meeting_<later ms>.wav` → that file still
  exists after A's window closes, while A's own file is gone** (finding 1)

These tests must not use `pumpAndSettle` around the undo window (the SnackBar animates and will not
settle) and must advance past the 10s duration, not the 4s default.

The repository is **not** changed, and that is intentional: `MeetingRepository` is a storage contract
and should not own filesystem policy. A test-level note records why, so the naive
"make `delete()` remove the file" change is not reintroduced later.

## Done criteria

- `melos run analyze` clean, `melos run test` green.
- STATUS.md's "Deleting a meeting never deletes its audio file" entry under *Known gaps / tech debt*
  amended or removed, and the subdirectory follow-up recorded.
