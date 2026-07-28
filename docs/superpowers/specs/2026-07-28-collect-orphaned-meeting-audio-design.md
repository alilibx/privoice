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

Its entire surface is one method:

```dart
/// Deletes meeting audio files in this directory that no meeting references.
/// Returns how many files were removed.
Future<int> collect(Iterable<String> referencedPaths)
```

`collect` is the whole mechanism. It is not a private helper behind two public methods — one method,
two call sites.

### Call sites

| When | Purpose |
|---|---|
| `HomeScreen._delete`, after the SnackBar closes | reclaims the file promptly |
| App startup (`main.dart`), after the repository opens | catches the app-kill case, and anything already leaked by past installs |

The startup call is also the migration story: existing users with already-orphaned files get them
reclaimed on the next launch, with no extra code.

In both cases `referencedPaths` is `(await repository.all()).map((m) => m.audioPath)` — the live row
set, read at the moment of collection, never a cached list.

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

### 3. A documented precondition

`ImportScreen` writes its WAV and inserts the `Meeting` row only after transcription completes —
minutes later for a long file. **During that window the WAV is legitimately unreferenced**, and a
concurrent `collect` would delete the user's in-progress import.

Today this cannot happen: both capture screens (`RecordScreen`, `ImportScreen`) are pushed *above*
Home, so neither call site can fire mid-capture, and the startup sweep runs before any capture is
possible. That is a property of the current navigation, not of `collect` itself, so it goes in the doc
comment as an explicit precondition:

> Only call when no capture or import is in flight.

If that ever stops holding — a periodic sweep, a background task, a settings-screen "reclaim space"
button — the correct fix is to make in-flight files unmistakable rather than to weaken the sweep:
write to a `.part` suffix and rename on commit, or move meeting audio into a dedicated subdirectory.
Recording this now is the point; it is the kind of latent trap that otherwise gets discovered by
deleting someone's two-hour import.

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

`HomeScreen` widget tests for the two paths that matter, with the store injected:

- delete → tap **Undo** → the file still exists
- delete → let the SnackBar close → the file is gone

The repository is **not** changed, and that is intentional: `MeetingRepository` is a storage contract
and should not own filesystem policy. A test-level note records why, so the naive
"make `delete()` remove the file" change is not reintroduced later.

## Done criteria

- `melos run analyze` clean, `melos run test` green.
- STATUS.md's "Deleting a meeting never deletes its audio file" entry under *Known gaps / tech debt*
  amended or removed, and the subdirectory follow-up recorded.
