# Foreground-service model downloader

**Date:** 2026-07-11
**Status:** Approved design
**Workstream:** Follow-up from R3/R5 (see STATUS "Known gaps → Model delivery")

## Problem

R3's model download runs in-process on the main isolate (streamed HTTP + Range
resume, `ModelDownloader.install`), kept alive only by a screen wakelock (R3
fix). On the Redmi it stalls the moment the screen locks / the app is
backgrounded or swiped away — the OS suspends the process and drops the socket;
the user must reopen to resume. The deferred fix is a true OS foreground-service
download that survives all of that.

## Direction (from brainstorming)

Replace the download **transport** with `background_downloader` (native
WorkManager/URLSession engine + foreground service + progress notification +
built-in resume), keeping everything above it — `ModelManager`, the download UI,
and `ModelDownloader`'s public interface — unchanged. Prime the notification
permission with a new onboarding step.

## `ModelDownloader` — internals rewritten, interface unchanged

Public surface preserved exactly (so `ModelManager` + its `FakeModelDownloader`
tests are untouched):
- `Future<bool> isInstalled(ModelSpec)` — unchanged (expected files on disk).
- `Future<String> pathTo(ModelSpec, String fileName)` — unchanged.
- `Future<void> install(ModelSpec, void Function(ModelInstallProgress))` —
  reimplemented over `background_downloader`.

New `install` behavior:
1. If already installed, emit `Ready` and return (unchanged idempotence).
2. For each `ModelFile`: build a `DownloadTask` targeting **the exact dir
   `PlatformPaths` reads from** — `BaseDirectory.applicationSupport` with
   `directory: 'models/${spec.subdir}'` and `filename: file.fileName`. (This
   MUST match `PlatformPaths.subdir`, which lives under
   `getApplicationSupportDirectory()/models/<subdir>` — not documents — or
   `isInstalled` will never find the downloaded files.) Run it with a progress
   callback → `onProgress(ModelInstallProgress(..., fraction, 'Downloading…'))`.
   Progress fraction reserves the top ~4% for extraction on archive models (as
   today). If the plugin's `BaseDirectory`/`directory` composition doesn't
   resolve to the identical absolute path `PlatformPaths.subdir(spec.subdir)`
   returns, fall back to `BaseDirectory.root` with the absolute path from
   `PlatformPaths` — the invariant is: file lands where `isInstalled` looks.
3. **Fallback mirror preserved:** try `file.url`; on failure and if
   `file.fallbackUrl != null`, retry with it (the plugin has its own retries;
   this is the source-fallback loop).
4. `isTarBz2` files: after the download completes, run the existing
   `_extractTarBz2` in a background isolate (`compute`) → `onProgress(...,
   'Extracting…')`, then delete the archive. (This logic is reused verbatim.)
5. Emit `Ready`.

Resume is now the plugin's responsibility (it resumes partial downloads across
app restarts). The old manual HTTP `Range` code and `http.Client` usage are
removed from `ModelDownloader`.

## Notification + permission

- Configure once (app start or first use):
  `FileDownloader().configureNotification(running: TaskNotification('Downloading
  models', '{progress}'), complete: ..., error: ..., progressBar: true)`.
- **Onboarding gains a 4th page** ("Keep you posted" — why the progress
  notification helps). Its **Start** button:
  1. requests `POST_NOTIFICATIONS` (via the plugin's permissions API or
     `permission_handler`);
  2. calls `SettingsService.setOnboardingComplete(true)`;
  3. starts `ModelManager.instance.ensureDefaultSet()`;
  4. enters the app.
- **Denied permission is non-fatal:** the foreground-service download still runs
  to completion; only the notification is suppressed.

## Android manifest

Add what `background_downloader` documents:
- `POST_NOTIFICATIONS` permission (Android 13+).
- Its foreground-service declaration / `dataSync` service type as required by the
  plugin version, plus any `WorkManager` entries the plugin needs.
(Exact entries per the installed plugin version's README — verified at build.)

## Kept unchanged

- `ModelManager` — full interface, state machine, and the R3 wakelock (harmless
  alongside the service; leaving it avoids churning the wakelock tests).
- The Home `_DownloadBanner` and per-model gating.
- `ModelSpec`/`ModelCatalog`, `expectedFiles` verification, staged STT-then-LLM
  ordering.
- The Settings 3B download (routes through the same `ModelDownloader`).

## Testing

- **Unchanged & green:** `ModelManager` tests (fake downloader), privacy gate,
  all widget tests.
- **Onboarding widget test:** updated for the 4th page (advance 4 screens; Start
  fires `onDone`; Skip still fires `onDone`).
- **Native download path:** not unit-testable (platform engine) — this is the
  honest limitation. Covered by the CI Android native-build gate (compiles the
  plugin) + **on-device verification on the Redmi**: start the download, then
  lock the screen / background the app / swipe it away, and confirm it runs to
  completion (notification visible if permission granted) and the app unlocks
  features when files land.
- No network is introduced beyond the existing model URLs; the offline
  transcription flow stays network-free (privacy gate).

## Risks

- `background_downloader` API/manifest specifics vary by version — the
  `ModelDownloader` rewrite is the part most likely to need on-device iteration.
- Xiaomi/MIUI is aggressive even with foreground services; on-device testing is
  the real gate. If MIUI still kills it, the resume-on-relaunch (plugin) remains
  the backstop — strictly better than today.

## Out of scope

iOS specifics beyond what the plugin gives for free, download pause/cancel UI,
and per-file retry tuning.

## Affected files

- `apps/mobile/pubspec.yaml` — add `background_downloader` (+ `permission_handler`
  if used for the prompt).
- `apps/mobile/android/app/src/main/AndroidManifest.xml` — permission + service
  entries.
- `packages/models/lib/src/model_downloader.dart` — rewrite `install` internals;
  drop manual HTTP/Range; keep `_extractTarBz2`, `isInstalled`, `pathTo`.
- `apps/mobile/lib/screens/onboarding_flow.dart` — 4th priming page.
- `apps/mobile/lib/screens/app_bootstrap.dart` — request notification permission
  on onboarding completion (before `ensureDefaultSet`).
- `apps/mobile/lib/` — notification configuration at startup (e.g. in `main`).
- Tests: `onboarding_flow_test.dart` updated for 4 pages.
