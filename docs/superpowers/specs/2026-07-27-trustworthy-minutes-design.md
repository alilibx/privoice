# Trustworthy minutes — design

**Date:** 2026-07-27
**Slice:** A (mobile, on-device) — first of the batch decomposed on 2026-07-27
**Status:** approved, ready for implementation plan

## Problem

Two defects, both observed on a real run:

1. **Fabricated minutes.** During the iOS bring-up (2026-07-27), a 13-second
   recording transcribed to exactly `"So is it working?"` — four words. The app
   summarized it anyway, and the 1B model invented a full meeting: three "Key
   Points" about project timelines and UI design concepts, a "Decision" to
   proceed to testing and deployment, and four action items including
   `"The design team will provide a detailed design document by [Deadline]."`
   None of it happened. `_generateOverview` in `transcript_screen.dart` gates
   only on `_transcript.isEmpty`, so any non-empty transcript reaches the LLM.
   This is the worst possible failure for a meeting-minutes product: confident,
   plausible, entirely false output that a user might forward to colleagues.

2. **Minutes and action items are read-only.** The model gets names, deadlines,
   and wording wrong. There is no way to correct it — minutes render as
   Markdown, and action items support only check-off.

## Scope

**In:** the insufficiency guard, editable minutes, editable/addable/deletable/
reorderable action items, and the split of `transcript_screen.dart`.

**Out, deliberately:** RMS/silence DSP over the WAV (belongs with audio import,
slice B), online models (slice E), PDF/Word export (S4). Speaker diarization.

## Architecture

### `packages/ai` — `SummarizeGate`

Pure Dart, no Flutter import, so it unit-tests without a widget harness.

```dart
enum GateOutcome { sufficient, tooFewWords, tooSparse }

class GateVerdict {
  final GateOutcome outcome;
  final int wordCount;
  final double wordsPerMinute;
  bool get sufficient => outcome == GateOutcome.sufficient;
}

class SummarizeGate {
  static const minWords = 30;
  static const minWordsPerMinute = 20;
  static const densityFloorMs = 60_000;

  static GateVerdict assess({
    required String transcript,
    required int durationMs,
  });
}
```

Rules, in order:

1. Word count `< minWords` → `tooFewWords`.
2. Otherwise, **only if `durationMs >= densityFloorMs`**, words-per-minute
   `< minWordsPerMinute` → `tooSparse`.
3. Otherwise `sufficient`.

The density floor exists so a deliberate 15-second dense voice note is judged
on word count alone and never fails a rate check. `durationMs <= 0` skips the
density rule entirely rather than dividing by zero.

Words are counted by splitting on whitespace runs after trimming, discarding
empty tokens. No punctuation stripping — a 30-word threshold does not need that
precision, and keeping it simple keeps it predictable.

### `packages/core` — one new field

`Meeting.minutesEditedAt` (`DateTime?`), persisted as `minutes_edited_at
INTEGER` (epoch ms, nullable). Schema goes to **v4** with an `onUpgrade` branch
following the existing v2/v3 pattern:

```dart
if (oldVersion < 4) {
  await db.execute('ALTER TABLE meetings ADD COLUMN minutes_edited_at INTEGER');
}
```

Its only job is to drive the Regenerate confirmation. Action items need **no**
schema change: they already serialize as a JSON array, so reorder is a rewrite
in new order, and manual items are ordinary `ActionItem` rows.

### `apps/mobile` — split the meeting screen

`transcript_screen.dart` is 632 lines before this work. Adding an editor, a
blocked state, and a reorderable list to it would make it unmaintainable, so
the Overview half moves out:

| File | Responsibility |
|---|---|
| `screens/overview_tab.dart` | Renders minutes, action items, the blocked state, and Regenerate |
| `screens/minutes_editor_screen.dart` | Full-screen raw-Markdown editor |
| `widgets/action_item_list.dart` | Checkable, editable, reorderable item list |
| `screens/transcript_screen.dart` (kept) | Scaffold, tabs, rename, share, generation orchestration |

Generation orchestration stays in `transcript_screen.dart` because it owns the
`Meeting` state and the repository handle; the new widgets take values and
callbacks, so each is testable in isolation with no repository.

## Behaviour

### The guard

Both entry points — `_generateOverview` and the auto-generate-on-first-open
path — consult `SummarizeGate` **before** any LLM call. A thin recording
therefore costs zero inference and cannot produce invented minutes.

The blocked state is **derived at render time** from transcript + duration, not
persisted as a new `MeetingStatus`. This avoids a second migration and means
old meetings re-evaluate correctly if the thresholds are ever tuned.

**Minutes that already exist are never retroactively hidden or deleted.** A
meeting summarized before this guard shipped — including the fabricated
"So is it working?" one now on the simulator — keeps rendering its minutes. The
gate governs *generation*, not display.

This forces a fix to the existing regenerate path: `_regenerate` today sets
`minutes: ''` and *then* calls `_generateOverview`. If the gate blocked after
that clear, the user's minutes would be destroyed and nothing would replace
them. The gate must therefore be consulted **before** the field is cleared, and
existing minutes must survive a blocked regenerate untouched.

Overview, when blocked, shows:

- Heading: *"Not enough speech to summarize"*
- Reason with real numbers: `tooFewWords` → *"Only 4 words in 0:13."*;
  `tooSparse` → *"18 minutes of audio but only 40 words — mostly silence."*
- The transcript itself, below, so nothing is hidden from the user.
- A secondary **Summarize anyway** button. It sets a one-shot in-memory
  override (not persisted) and runs the normal generation path.

Home's subtitle shows **"Transcript only"** for a meeting that has a transcript
but no minutes, replacing today's blank.

### Editing minutes

Edit → `MinutesEditorScreen`, raw Markdown in a full-height `TextField`.

- **Save** persists the text and stamps `minutesEditedAt = now`.
- **Cancel** with unsaved changes asks to confirm discarding.
- Saved text renders as Markdown again in Overview.

### Editing action items

Tap an item to edit its text; `+ Add item` appends a new one; delete removes
one; drag reorders (`ReorderableListView`). Every mutation persists
immediately, matching how check-off already behaves — there is no explicit save
for the list.

### Independence and regeneration

Saving minutes never rewrites the item list; editing items never rewrites the
minutes. They are separate fields after generation.

**Regenerate** re-runs the whole overview (minutes + items + title), as it does
today — a partial re-run is more confusing than useful. But when
`minutesEditedAt != null` or any item has been hand-modified, it first shows a
confirm dialog: *"Regenerating replaces your edits. Continue?"*

Tracking "hand-modified items" needs no schema change: the screen compares the
current list against the last generated list held in memory for the session,
and treats a non-null `minutesEditedAt` as the durable signal across launches.
A user who edits items, kills the app, relaunches, and hits Regenerate without
touching the minutes will not be warned about the item edits — accepted, since
Regenerate is an explicit destructive action already labelled as such, and the
alternative is a second column for a rare path.

## Testing

Per `TESTING.md`, tests ship with the slice, runnable from a fresh clone.

**Unit — `packages/ai/test/summarize_gate_test.dart`**
- empty and whitespace-only transcript → `tooFewWords`
- **the real regression: 4 words / 13 000 ms → `tooFewWords`**
- boundary: 29 → blocked, 30 → sufficient, 31 → sufficient
- 40 words / 18 min → `tooSparse`
- 40 words / 15 s → `sufficient` (below the density floor, word count carries)
- 30 words / `durationMs = 0` → `sufficient`, no divide-by-zero
- exactly at the density floor: 30 words / 60 000 ms → `sufficient`
  (30 wpm clears the 20 wpm bar); 10 words / 60 000 ms → `tooFewWords`, since
  the word rule is checked first
- `wordCount` / `wordsPerMinute` are reported accurately for the UI copy

**Unit — `packages/core`**
- v3→v4 migration preserves existing rows and their action items
- `minutesEditedAt` round-trips through `toRow`/`fromRow`, including null
- item reorder round-trips in the new order

**Widget — `apps/mobile`**
- blocked state renders the heading, the numeric reason, and the transcript
- **Summarize anyway** invokes generation (fake `AiService`)
- a sufficient transcript auto-generates on first open; a thin one does not
  (asserting the fake engine was never called — this is the regression test)
- editor: save persists and stamps, cancel-when-dirty confirms
- items: add, edit, delete, reorder each persist
- Regenerate confirm appears only when edits exist, and cancelling it leaves
  minutes untouched
- **a blocked regenerate preserves existing minutes** (the data-loss path:
  thin transcript + existing minutes + Regenerate → minutes still there)
- Home shows "Transcript only" for transcript-without-minutes

**Gate:** `melos run analyze` clean, `melos run test` green including the 104
existing tests.

## Risks

- **Threshold tuning.** 30 words / 20 wpm are first estimates, not measured.
  They are named constants in one file, and the derived (unpersisted) blocked
  state means changing them re-evaluates old meetings correctly.
- **`ReorderableListView` inside a scrolling tab** needs care over shrink-wrap
  and scroll physics; if it fights the tab's scroll view, the fallback is a
  reorder mode toggle rather than always-on drag handles.
