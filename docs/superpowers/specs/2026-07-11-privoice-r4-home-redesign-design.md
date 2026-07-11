# R4 — Home screen reimagining

**Date:** 2026-07-11
**Status:** Approved design
**Workstream:** Redesign R4 (see STATUS.md)

## Problem

The current Home (`apps/mobile/lib/screens/home_screen.dart`) is functional
Material 3: an app-bar (title + toggle-search + on-device badge + settings), a
`Record` FAB, and a list of meeting **cards** (title, date·duration, preview,
Minutes/actions pills) with an empty state and swipe-to-delete. It works but is
generic. R4 reimagines it into the elevated calm-teal language (R1 tokens).

## Direction (from brainstorming + mockups)

A **library-first Home with a persistent bottom record dock**:

- The meeting **library fills the screen** as a dense, grouped list (not cards).
- **Recording is anchored at the bottom** in a persistent dock — thumb-reachable
  — with a waveform motif and the mic button riding the dock's top edge.

This replaces the top FAB + card list. All current functionality is preserved
(search, swipe-to-delete + undo, per-model R3 gating, on-device badge, settings).

## Layout

A `Scaffold` (no FAB) with a column body:

1. **Header** — `Privoice` title (left), an on-device lock badge + settings icon
   (right). Flat, page-bg background (R1 app-bar style). Not a scroll-away
   `AppBar`; a lightweight header row so the search + list + dock compose cleanly.
2. **Search field** — always visible (not a toggle). A rounded search input
   ("Search meetings") that filters the list live.
3. **Meeting list** — the scrollable region (`Expanded`), grouped and dense.
4. **Record dock** — pinned at the bottom, above the list's scroll area.

The R3 **download banner** (`ModelManager` not `allReady`) still renders between
the search and the list, unchanged.

## Meeting list

- **Dense rows**, not cards. Each row: leading **status dot** · title (`titleSmall`
  weight) · one-line meta · trailing chevron. Rows sit in a white rounded
  container per group with hairline dividers between them (`outlineVariant`).
- **Meta line:** `relative time · duration` plus, when present, `· Minutes` and
  `· N actions`. Relative time: "2h ago", "Tue", "12 Jun" (today→hours, this
  week→weekday, older→date).
- **Grouping into buckets by `createdAt`:** **Today**, **This week** (last 7 days,
  excluding today), **Earlier**. Empty buckets are omitted. Section labels are
  small uppercase muted text.
- **Swipe-to-delete + undo** preserved (`Dismissible` + snackbar), same behavior
  as today.

### Status dot
Derived from `Meeting.status` (`enum MeetingStatus { recorded, transcribing,
done, failed }`):
- **done** → green (`tertiary` / `#2F8F6B`)
- **transcribing** → amber (`#EF9F27`), with a subtle pulse
- **recorded** (captured, not yet transcribed) → muted grey (`onSurfaceVariant`)
- **failed** → red (`error`)

No new persistence states are added in R4.

## Record dock (bottom, persistent)

A rounded-top white surface pinned at the bottom:
- A faint **waveform** motif (static bars) across the dock.
- The **mic button** — a teal circle — riding the dock's top edge (negative top
  margin + white ring), the focal element.
- Caption: **"Tap to record"** + "Transcribed privately on your phone".

**R3 gating integration (required):** the dock reads `ModelManager` (same
optional-injected pattern as today's `HomeScreen`):
- When `sttReady` → tapping opens `RecordScreen`.
- When `!sttReady` → the dock renders a subdued "Preparing…" state (determinate
  progress on the mic button, driven by `stateOf(parakeetStt).fraction`, matching
  the R3 approach), and a tap shows the existing snackbar
  ("Speech-to-text is still downloading (N%)") instead of navigating.

The dock rebuilds on `ModelManager` changes (wrap in `ListenableBuilder`, as
Home already does).

## Empty state

When there are no meetings, the list region shows an invitation ("Record your
first meeting — it's transcribed and summarized right here on your phone."), and
the **record dock stays present**. When a search has no matches, show a compact
"No matches" state in the list region (dock still present).

## Search

Live filter over the loaded meetings (title + transcript contains, case-
insensitive) — same predicate as today. Filtering happens before grouping, so
groups reflect the filtered set. Empty query → all meetings.

## Motion

- **Staggered row entrance** — reuse the R1 `_Entrance` fade/slide feel for rows
  (bounded animation, `pumpAndSettle`-safe — no indefinite tickers).
- **Transcribing pulse** — a gentle opacity pulse on the amber status dot only.
  Must be bounded/removable so tests settle (a repeating controller is fine in
  the app but the row must not block `pumpAndSettle`; if that's a risk, render a
  static amber dot under test via the existing patterns).

## Components / files

- Rewrite `apps/mobile/lib/screens/home_screen.dart`:
  - `HomeScreen` keeps its constructor (`repository`, `ai`, `themeMode`,
    optional `modelManager`) so `AppBootstrap` and all tests are unaffected.
  - New private widgets: `_Header`, `_SearchField`, `_MeetingRow`, `_StatusDot`,
    `_GroupLabel`, `_RecordDock`, plus grouping helpers. Keep the file focused; if
    it grows unwieldy, extract `record_dock.dart` and/or `meeting_row.dart` under
    `screens/home/`.
- Add a pure grouping helper (testable): `groupMeetings(List<Meeting>, now)` →
  ordered `[(label, meetings)]` buckets. Put it in the same library and unit-test
  it directly (pure function, no widgets).
- No changes to `MeetingRepository`, `Meeting`, `ModelManager`, or navigation
  targets (`RecordScreen`, `TranscriptScreen`).

## Testing

- **Unit:** `groupMeetings` — Today/This week/Earlier bucketing at boundaries
  (now, 6 days ago, 30 days ago), empty buckets omitted, ordering newest-first.
- **Widget (Home):**
  - renders grouped sections + rows for a seeded list;
  - **record dock**: enabled/navigates when `sttReady`; "Preparing…" + snackbar
    (no navigation) when `!sttReady`;
  - status dot color maps from `MeetingStatus`;
  - search filters rows and regroups; no-match shows the empty search state;
  - empty repository shows the invitation and the dock is present;
  - swipe-to-delete still fires + undo restores.
- **Regression:** existing Home/privacy-gate/bootstrap tests updated only as
  needed for the new widget tree (e.g. `find.text('Record')` may change — update
  finders); full suite + zero-network privacy gate stay green.

## Out of scope

Record screen redesign (R5), Minutes/transcript redesign (R6), diarization,
new persistence states, and the foreground-service downloader (separate
follow-up) are all out of scope for R4.
