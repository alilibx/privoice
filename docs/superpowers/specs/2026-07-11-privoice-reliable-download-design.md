# Reliable model download — no extraction, resumable across kill

**Date:** 2026-07-11
**Status:** Approved design
**Workstream:** Follow-up hardening of the foreground-service downloader

## Problem (observed on the Redmi)

The foreground-service download (background_downloader) works, but on-device
testing exposed the real weak link: the STT model ships as a **487 MB
`.tar.bz2`** that we decompress in a pure-Dart `compute` isolate. On the low-end
Helio G that extraction pinned one core at 100% for ~6 minutes with the UI stuck
at 48% (no progress feedback), and it is **not covered by the foreground
service** — swiping the app away during extraction would lose it. Separately,
the plugin's per-download-task "complete" notification fired **"Models ready"**
when only the STT *download* (not extraction, not the LLM) was done, and the
awaited `download()` with fresh task ids does not resume across process death.

## Direction (approved)

Make the whole install **native downloads only**, resumable across process
death, with honest progress/notifications.

### 1. Eliminate extraction — download pre-extracted STT files

`csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8` on Hugging Face (the same
k2-fsa maintainer that publishes the `.tar.bz2`, CDN-backed, Range/resume) hosts
the four files individually at the exact sizes already verified on-device.

Change `ModelCatalog.parakeetStt` to **four `ModelFile`s**, no archive:
- `https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/main/encoder.int8.onnx` (652 MB)
- `.../resolve/main/decoder.int8.onnx` (11.8 MB)
- `.../resolve/main/joiner.int8.onnx` (6.36 MB)
- `.../resolve/main/tokens.txt` (93.9 kB)

`subdir` and `expectedFiles` stay the same four filenames; `approxBytes` ≈ 671 MB.
`isTarBz2` is removed from every spec. **Delete** `_extractTarBz2`, the `compute`
call, the `_ExtractArgs` type, and the `archive` dependency from
`packages/models`.

### 2. Resumable-across-kill download

Rewrite `ModelDownloader` to use the plugin's durable path (public interface
unchanged — `isInstalled`/`pathTo`/`install(spec, onProgress)`):

- App startup (`main`): `FileDownloader().trackTasks()` (persist task state to the
  plugin DB) then `await FileDownloader().start()` (on launch this reschedules
  tasks the OS killed and resumes background updates) — this is what recovers an
  interrupted download after process death/swipe-away.
- `install(spec, onProgress)`: for each `ModelFile`, `enqueue` a `DownloadTask`
  with a **stable, deterministic `taskId`** (e.g. `'${spec.id}::${file.fileName}'`),
  `group: spec.id`, `baseDirectory: applicationSupport`, `directory:
  'models/${spec.subdir}'`, `filename: file.fileName`, `updates:
  Updates.statusAndProgress`, `allowPause: true`. Await completion by listening
  to `FileDownloader().updates` for each task id (a `Completer` per file that
  completes on `TaskStatus.complete` and errors on `.failed`/`.notFound`).
  Aggregate per-file progress into the model's fraction (weight by size, or
  simple average) → `onProgress(..., 'Downloading…')`. Emit `Ready` when all the
  spec's files exist at `pathTo(...)`.
- Because task ids are stable and `start()` reschedules killed tasks, a relaunch
  re-attaches to / resumes the same download rather than restarting; a file
  already fully present is skipped (plugin's "skip if destination present" +
  our `isInstalled` fast-path).
- Source-fallback (`file.url` → `file.fallbackUrl`) preserved per file.
- The primary-URL failure path and existence-verification at `pathTo` are kept.

`ModelManager` is unchanged — `install` still returns a `Future<void>` that
completes when the spec is installed, so `ensureDefaultSet`'s STT-then-LLM
sequencing and state machine are untouched (and its `FakeModelDownloader` tests
stay green).

### 3. Honest notification

Do not present the per-file "complete" pop as "Models ready". Options (pick in
the plan): a group-completion notification that only says done when the whole
default set is installed, or suppress the plugin `complete` notification and let
the in-app Home banner be the source of truth for "ready". The `running`
notification (progress) stays.

## Testing

- **Unchanged & green:** `ModelManager` tests (fake downloader), privacy gate, all
  widget tests.
- **`ModelCatalog` test (packages/models):** update for STT = 4 individual files,
  none `isTarBz2`, expectedFiles unchanged; assert the HF resolve URLs and that
  no spec is an archive anymore.
- **Native download/resume path:** not unit-testable — build-verified (CI native
  gate) + **on-device Redmi verification**: fresh install, then (a) confirm no
  extraction stall / smooth progress, (b) swipe the app away mid-download and
  relaunch → it **resumes** (not restarts), (c) the "ready" signal only appears
  when both models are actually installed.
- No new network beyond the model URLs; offline transcription stays network-free.

## Risks

- The `enqueue` + `updates`-listener + `start()`/`trackTasks` wiring is the
  fiddly part; get it right against the installed 9.5.5 API (read its
  `doc/lifecycle.md` + example). Sequence the work so extraction-removal (the
  actual observed problem) lands first and independently.
- HF third-party dependency (official maintainer). A future step could mirror the
  four files to our own bucket for zero external reliance — out of scope here.

## Affected files

- `packages/models/lib/src/model_spec.dart` — STT → 4 files; drop `isTarBz2`
  usage; adjust `approxBytes`.
- `packages/models/lib/src/model_downloader.dart` — remove extraction + `archive`;
  rewrite `install` over `enqueue`/`updates`/stable task ids.
- `packages/models/pubspec.yaml` — drop `archive` (and `http` if now unused).
- `packages/models/test/model_catalog_test.dart` — update for 4 STT files.
- `apps/mobile/lib/main.dart` — `trackTasks()` + `start()`; honest notification config.
- `apps/mobile/pubspec.yaml` — background_downloader already present.

## Out of scope

Own-bucket mirror, iOS specifics, pause/cancel UI, and the R6 (minutes) slice.
