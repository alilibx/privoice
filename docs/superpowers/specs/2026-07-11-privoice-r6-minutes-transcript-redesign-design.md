# R6 — Meeting screen redesign (Overview + Transcript)

**Date:** 2026-07-11
**Status:** Approved design
**Workstream:** Redesign R6 (see STATUS.md)

## Problem

The current meeting screen (`apps/mobile/lib/screens/transcript_screen.dart`)
opens on the **Transcript** tab with **Minutes** second, and drives AI through a
horizontal bar of manual buttons (Summarize / Action items / Ask). It predates
the R1 calm-teal language, buries the summary people actually come back for, and
its action items are non-interactive chips. Meeting titles are a bare
`Meeting DD/MM HH:MM` placeholder.

## Direction (from brainstorming)

Reframe the screen around what a user wants from a finished meeting — a clean,
skimmable summary — and bring it into the calm-teal language:

- **Overview (default tab)** — a reading dashboard: AI-generated **title** →
  **minutes** (markdown reading layout) → **checkable action items**.
- **Transcript (second tab)** — the raw text, restyled (selectable, comfortable
  reading measure).

The summary appears **automatically**: opening a fresh meeting runs one on-device
generation pass (title + minutes + action items) instead of making the user tap
separate buttons.

Scope: redesign + auto-generate + checkable/persisted action items + AI title +
inline rename + richer sharing + a disabled Export stub. **No** real PDF/Word
export (S4), diarization, audio playback, or R7 delight polish.

## Screen structure

`TranscriptScreen` keeps its two-tab `TabController` but flips the order and
restyles both tabs:

- **Tab 0 — Overview** (default). A scroll view:
  1. (title lives in the app bar, not the body — see "AI title")
  2. **Minutes** — `MarkdownBody` in a calm reading layout (generous measure,
     line-height ~1.5), with the existing reveal-fade.
  3. **Action items** — a checkable list (see "Checkable action items").
  4. Bottom: a persistent **Ask** entry.
- **Tab 1 — Transcript**. `SelectableText` in the same reading layout as today,
  restyled to theme tokens.

App bar:
- **Title** — tap to rename inline (see "Inline rename").
- **Overflow menu (⋮)** — Share minutes · Share transcript · Share action items ·
  Copy all · **Export… (disabled, "Coming soon")**.

The old `_SmartActionBar` (Summarize / Action items / Ask buttons) is removed;
generation is automatic and Ask moves to the persistent bottom entry. A manual
**Regenerate** action remains (see "Auto-generate").

## Auto-generate on open (one pass)

When the Overview builds and the meeting has a transcript but **no minutes yet**:

- If the LLM is **ready** (`ModelManager.llmReady`): kick off a single generation
  pass automatically — **title + minutes + action items** — reusing the existing
  streaming (`onToken`) and progress (`onProgress`) callbacks for the calm
  sparkle/streaming state and the "On-device · nothing leaves your phone" line.
- If the LLM is **not ready** (still downloading/preparing): show a calm
  "Preparing on-device AI…" hold; when `ModelManager` notifies `llmReady`, the
  pass auto-starts. (The screen already listens to `ModelManager` via
  `ListenableBuilder`.)
- On **failure**: a restyled error state with **Retry**.

The pass is **guarded to fire once** — the trigger condition is "no minutes yet",
so once minutes are cached (`repository.update`) it will not re-fire on rebuild or
tab switches. A user can force a fresh pass via **Regenerate** (in the overflow or
below the minutes), which re-runs minutes + action items (title is only
(re)generated while still the placeholder — see below).

Generation order within the pass (sequential, each cached as it lands so a
mid-pass kill still leaves partial progress persisted):
1. **minutes** (streamed) → cache.
2. **action items** from the minutes (short, coherent source) → cache.
3. **title** from the transcript → cache (only if title is still the default).

## AI-generated title

- New `AiService.generateTitle(String transcript) → Future<String?>` — asks the
  on-device LLM for a short, specific title (~3–6 words, no date, no quotes). It
  trims/one-lines the result and caps length; returns `null` if the model is
  unavailable.
- Generated **as part of the Overview auto-pass** (not in the record pipeline) —
  this keeps R6 self-contained, keeps the record→transcribe→persist flow fast and
  free of an LLM dependency, and shows the title settling in alongside the
  minutes.
- It **only replaces the default placeholder**. A helper
  `bool _isDefaultTitle(String)` recognises the `Meeting DD/MM HH:MM` shape; if
  the title has been renamed by the user (or already AI-named), the pass leaves it
  untouched. This makes rename and regenerate safe.
- `record_screen._defaultTitle()` is unchanged — it remains the placeholder the
  Overview later upgrades.

## Checkable action items (persisted) — data-model change

Action items become interactive to-dos with a saved done-state.

**Model (`packages/core`):**
- New `class ActionItem { const ActionItem({required this.text, this.done = false});
  final String text; final bool done; ActionItem copyWith({bool? done});
  Map<String,Object?> toJson(); factory ActionItem.fromJson(Map); }`.
- `Meeting.actionItems` changes `List<String>` → `List<ActionItem>`.
  `copyWith`, constructor default (`const []`) unchanged in shape.
- **Serialization:** store the list as a JSON array string in the existing
  `action_items` column.
  - `toRow`: `jsonEncode(actionItems.map((a) => a.toJson()).toList())`, or `null`
    when empty.
  - `fromRow`: try `jsonDecode`; if it yields a `List`, map to `ActionItem`s.
    **Fallback** for legacy/un-migrated rows: split on `\n` →
    `ActionItem(text: line, done: false)`. This keeps `fromRow` robust regardless
    of migration timing.

**Migration (`SqfliteMeetingRepository`):**
- Bump `schemaVersion` 2 → 3.
- `onUpgrade` `if (oldVersion < 3)`: read every row's `action_items`, and for any
  non-null legacy newline value rewrite it as the JSON array (`done:false`). Rows
  already JSON (fresh installs) are unaffected. New `onCreate` schema is unchanged
  (still an `action_items TEXT` column; only the encoding differs).

**AI seam:** `AiService.actionItems(source)` still returns `List<String>?`; the
screen maps each to `ActionItem(text: s)`. (Keeping the AI contract string-based
avoids leaking the storage type into the engine.)

**UI:**
- Each item is a checkbox row (calm-teal): tap toggles `done`, persists
  immediately via `repository.update(_meeting)`, strikes through, and sinks
  completed items to the bottom of the list. Keeps the staggered entrance
  animation for the initial reveal.

## Inline rename

- Tapping the app-bar title opens an inline edit (dialog or in-place text field)
  seeded with the current title; on save it `copyWith(title:)` + `update`s and
  updates the app bar. Empty/whitespace is rejected (keeps prior title).
- Because auto-title only overwrites the default placeholder, a manual rename is
  permanent.

## Sharing

- **Per-section**, via the overflow menu and/or inline affordances:
  - Share minutes · Share transcript · Share action items (rendered as a checklist
    text) — each through `share_plus`.
  - **Copy all** → clipboard: title + minutes + action items as plain text.
- **Export…** menu item is present but **disabled** with a "Coming soon" hint,
  reserving the S4 slot without shipping a dead control that looks active.

## Ask entry

- A **persistent bottom entry** on the Overview ("Ask about this meeting…") that
  opens the existing `AskSheet.show(...)` grounded in `minutes + transcript`
  (same context assembly as today). Replaces the old button-in-a-bar. Disabled
  with a subtle hint until the LLM is ready.

## Components / files

- `packages/core/lib/src/action_item.dart` *(new)* — `ActionItem` + JSON.
- `packages/core/lib/src/meeting.dart` — `actionItems` → `List<ActionItem>`;
  JSON `toRow`/`fromRow` with legacy fallback; `copyWith`.
- `packages/core/lib/privoice_core.dart` — export `ActionItem`.
- `packages/core/lib/src/meeting_repository.dart` — `schemaVersion` 3 +
  `onUpgrade` legacy→JSON conversion.
- `apps/mobile/lib/ai_service.dart` — add `generateTitle(transcript)`.
- `apps/mobile/lib/screens/transcript_screen.dart` — rewrite: Overview-first
  tabs, auto-generate pass (title+minutes+actions), checkable action list,
  inline rename, per-section share + overflow menu, disabled Export, persistent
  Ask entry. Remove `_SmartActionBar`.
- `apps/mobile/lib/screens/record_screen.dart` — unchanged (`_defaultTitle` kept).

## Testing

**Unit (core):**
- `ActionItem` JSON round-trip (`text`, `done`).
- `Meeting` serialization with `List<ActionItem>`: JSON `toRow`/`fromRow`
  round-trip; **legacy fallback** — a row whose `action_items` is a newline blob
  parses to items with `done:false`.
- Repository **v2→v3 migration**: seed a v2 DB with a legacy newline
  `action_items` row, open at v3, assert the row now reads as JSON `ActionItem`s
  with `done:false`. (in-memory ffi, mirroring existing repo tests.)

**Widget (app), with fake repo + fake AI:**
- **Auto-generate on open:** fake AI returns title + minutes + items; opening the
  Overview runs the pass, renders minutes + action items, updates the title, and
  **caches** (a second build does not re-run — assert the fake's call count).
- **Checkable persistence:** tapping an item's checkbox calls `repository.update`
  with `done:true`; rebuilding from the repo shows it checked.
- **AI preparing:** with `llmReady == false`, the Overview shows the "Preparing
  on-device AI…" hold and does **not** call the AI; flipping `llmReady` true
  triggers the pass.
- **Rename:** editing the title updates the app bar and persists; the auto-title
  step does **not** overwrite a renamed title.
- **Share:** invoking "Share minutes" / "Share transcript" routes the right body
  (assert via a share hook/fake).
- **Export disabled:** the Export menu item is present and disabled.

**Regression:** full suite (`melos run test`) + zero-network privacy gate stay
green — title/minutes/actions are all on-device; no network is introduced.

## Out of scope

Real PDF/Word export (S4), speaker diarization, audio playback, waveform,
standalone chat panel, and the R7 (empty/error delight) slice.
