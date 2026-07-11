# Reliable Model Download Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. On-device feature — the download/resume path can't be unit-tested; the gate for those steps is *the Android debug build compiles* + on-device verification (the user). `ModelManager`/`ModelCatalog` tests + build are the automated net.

**Goal:** Make model install reliable — download the STT model as 4 pre-extracted files (no more in-app `.tar.bz2` decompress), and make downloads resume across process-death/swipe-away — keeping `ModelDownloader`/`ModelManager` interfaces unchanged.

**Architecture:** STT becomes 4 individual HF files (drop the archive + `_extractTarBz2` + `archive` dep). `ModelDownloader.install` does per-file downloads with size-weighted aggregate progress. Then (Task 2) the transport moves to `enqueue` + `FileDownloader().trackTasks()`/`start()` + a `updates` listener with stable task ids, so an interrupted download resumes on relaunch.

**Tech Stack:** Flutter, `background_downloader` 9.5.5, Hugging Face CDN.

## Global Constraints

- **`ModelDownloader` public interface unchanged:** `isInstalled`/`pathTo`/`install(spec, onProgress)`/`ModelInstallProgress`. `ModelManager` untouched (its `FakeModelDownloader` tests must stay green).
- **Path invariant:** files land at `pathTo(spec, file.fileName)` = `getApplicationSupportDirectory()/models/<subdir>/<fileName>` (`BaseDirectory.applicationSupport` + `directory: 'models/${spec.subdir}'`).
- **No extraction anywhere** after Task 1 — no spec is an archive; delete `_extractTarBz2`/`_ExtractArgs`/`compute`/`archive` dep.
- **Preserve:** source-fallback (`file.url`→`file.fallbackUrl`), idempotent skip-if-installed, post-download existence check at `pathTo`, staged STT-then-LLM (in `ModelManager`).
- **No new network** beyond model URLs.
- **Plugin-API caveat:** use the installed 9.5.5 API; read its `doc/lifecycle.md` + example for `enqueue`/`updates`/`start`/`trackTasks`. Build + on-device are the gates.
- **Commands:**
  ```bash
  export PATH="/opt/homebrew/bin:$HOME/.pub-cache/bin:/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH"
  export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
  export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
  ```

---

## Task 1: Eliminate extraction — STT as 4 files, weighted progress

**Files:**
- Modify: `packages/models/lib/src/model_spec.dart`, `packages/models/lib/src/model_downloader.dart`, `packages/models/pubspec.yaml`, `packages/models/test/model_catalog_test.dart`

**Interfaces:**
- `ModelFile` loses `isTarBz2`, gains `final int approxBytes` (per-file size, default 0).
- `ModelDownloader` public surface unchanged.

- [ ] **Step 1: Update the catalog test (RED)**

In `packages/models/test/model_catalog_test.dart`, replace the parakeet + approxSizeLabel groups so they assert the new shape:
```dart
  group('parakeet STT spec', () {
    test('is 4 individual pre-extracted files (no archive)', () {
      final stt = ModelCatalog.parakeetStt;
      expect(stt.kind, ModelKind.stt);
      expect(stt.files.map((f) => f.fileName).toSet(), {
        'encoder.int8.onnx',
        'decoder.int8.onnx',
        'joiner.int8.onnx',
        'tokens.txt',
      });
      expect(stt.expectedFiles.toSet(), stt.files.map((f) => f.fileName).toSet());
      for (final f in stt.files) {
        expect(f.url, contains('huggingface.co'));
        expect(f.approxBytes, greaterThan(0));
      }
    });
  });

  test('no spec is an archive anymore', () {
    for (final s in [ModelCatalog.parakeetStt, ModelCatalog.llama1b, ModelCatalog.llama3b]) {
      for (final f in s.files) {
        expect(f.fileName, isNot(endsWith('.tar.bz2')));
      }
    }
  });
```
(Keep the `defaultSet` ordering test and the LLM `.gguf` test. Remove any `isTarBz2` assertion and the old `approxSizeLabel` expectations that assumed the archive size.)

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/models && flutter test test/model_catalog_test.dart`
Expected: FAIL — `isTarBz2` still referenced / parakeet still a single archive file.

- [ ] **Step 3: Rewrite `model_spec.dart`**

In `packages/models/lib/src/model_spec.dart`: in `ModelFile`, remove `isTarBz2` and add `final int approxBytes;` (constructor `this.approxBytes = 0`). Replace `parakeetStt` and add per-file `approxBytes` on the LLMs:
```dart
  static const parakeetStt = ModelSpec(
    id: 'parakeet-tdt-v3-int8',
    kind: ModelKind.stt,
    displayName: 'Speech-to-text (Parakeet v3)',
    subdir: 'parakeet-tdt-v3-int8',
    files: [
      ModelFile(
        url: 'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/main/encoder.int8.onnx',
        fileName: 'encoder.int8.onnx',
        approxBytes: 652 * 1024 * 1024,
      ),
      ModelFile(
        url: 'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/main/decoder.int8.onnx',
        fileName: 'decoder.int8.onnx',
        approxBytes: 12 * 1024 * 1024,
      ),
      ModelFile(
        url: 'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/main/joiner.int8.onnx',
        fileName: 'joiner.int8.onnx',
        approxBytes: 7 * 1024 * 1024,
      ),
      ModelFile(
        url: 'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/main/tokens.txt',
        fileName: 'tokens.txt',
        approxBytes: 1 * 1024 * 1024,
      ),
    ],
    expectedFiles: [
      'encoder.int8.onnx',
      'decoder.int8.onnx',
      'joiner.int8.onnx',
      'tokens.txt',
    ],
    approxBytes: 672 * 1024 * 1024,
  );
```
For `llama1b`/`llama3b`, add `approxBytes: <spec.approxBytes>` to their single `ModelFile` (e.g. 808 MB / 2020 MB) so the weighting has a value.

- [ ] **Step 4: Rewrite `model_downloader.dart` (drop extraction; weighted progress)**

Remove `import 'package:archive/archive.dart';` and `import 'package:flutter/foundation.dart';` (no more `compute`), the `_ExtractArgs` class, and `_extractTarBz2`. Replace `install` + `_downloadFile` so the per-file callback reports that file's 0..1 and `install` aggregates by `approxBytes`:
```dart
  Future<void> install(
    ModelSpec spec,
    void Function(ModelInstallProgress) onProgress,
  ) async {
    if (await isInstalled(spec)) {
      onProgress(_p(spec, 1, 'Ready'));
      return;
    }
    final totalBytes =
        spec.files.fold<int>(0, (s, f) => s + (f.approxBytes > 0 ? f.approxBytes : 1));
    final frac = <String, double>{for (final f in spec.files) f.fileName: 0.0};
    void report() {
      final agg = spec.files.fold<double>(
          0, (s, f) => s + frac[f.fileName]! * (f.approxBytes > 0 ? f.approxBytes : 1));
      onProgress(_p(spec, agg / totalBytes, 'Downloading…'));
    }

    for (final file in spec.files) {
      await _downloadFile(file, spec, (f) {
        frac[file.fileName] = f;
        report();
      });
      frac[file.fileName] = 1.0;
      report();
    }
    onProgress(_p(spec, 1, 'Ready'));
  }

  Future<void> _downloadFile(
    ModelFile file,
    ModelSpec spec,
    void Function(double fileFraction) onFileProgress,
  ) async {
    final urls = [file.url, if (file.fallbackUrl != null) file.fallbackUrl!];
    Object? lastError;
    for (final url in urls) {
      try {
        await _downloadFrom(url, file, spec, onFileProgress);
        if (!File(await pathTo(spec, file.fileName)).existsSync()) {
          throw StateError('downloaded file missing at expected path');
        }
        return;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? StateError('download failed: ${file.fileName}');
  }

  Future<void> _downloadFrom(
    String url,
    ModelFile file,
    ModelSpec spec,
    void Function(double) onFileProgress,
  ) async {
    final task = DownloadTask(
      url: url,
      filename: file.fileName,
      baseDirectory: BaseDirectory.applicationSupport,
      directory: 'models/${spec.subdir}',
      updates: Updates.statusAndProgress,
      retries: 3,
      allowPause: true,
    );
    final result = await FileDownloader().download(
      task,
      onProgress: (progress) {
        if (progress >= 0) onFileProgress(progress);
      },
    );
    if (result.status != TaskStatus.complete) {
      throw StateError('download ${result.status.name} for $url');
    }
  }
```
Keep `_p` and the `isInstalled`/`pathTo` methods.

- [ ] **Step 5: Drop the `archive` dependency**

In `packages/models/pubspec.yaml`, remove the `archive:` line (and `http:` if now unused — check first). Run `cd packages/models && flutter pub get`.

- [ ] **Step 6: Verify**

Run:
```bash
cd packages/models && flutter test          # catalog test green
cd /Users/ali/Development/me/apps/privoice && melos run analyze   # 6 packages clean
cd apps/mobile && flutter test test/model_manager_test.dart       # unchanged, green
cd apps/mobile && flutter build apk --debug  # compiles
```
Expected: all green; APK built.

- [ ] **Step 7: Commit**

```bash
git add packages/models/lib/src/model_spec.dart packages/models/lib/src/model_downloader.dart packages/models/pubspec.yaml packages/models/test/model_catalog_test.dart pubspec.lock
git commit -m "feat: download STT as pre-extracted files (drop tar.bz2 + in-app extraction)"
```

---

## Task 2: Resume across process-death (enqueue + start + tracking)

**Files:**
- Modify: `packages/models/lib/src/model_downloader.dart`, `apps/mobile/lib/main.dart`

**Interfaces:** `ModelDownloader` public surface still unchanged.

- [ ] **Step 1: Enable tracking + reschedule on launch**

In `apps/mobile/lib/main.dart`, after `configureNotification` + `configure(runInForeground)`, add:
```dart
  await FileDownloader().trackTasks();
  await FileDownloader().start(doRescheduleKilledTasks: true);
```
(`trackTasks` persists task state to the plugin DB; `start` reschedules tasks the OS killed and resumes background updates — the mechanism that recovers an interrupted download after process death. Confirm exact method names against the installed 9.5.5 `file_downloader.dart`.)

- [ ] **Step 2: Migrate `_downloadFrom` to enqueue + updates listener with a stable task id**

Rewrite `_downloadFrom` to enqueue (instead of `download()`) with a **deterministic** `taskId` so a relaunch re-attaches to / resumes the same task, and await completion via the `updates` stream:
```dart
  Future<void> _downloadFrom(
    String url,
    ModelFile file,
    ModelSpec spec,
    void Function(double) onFileProgress,
  ) async {
    final taskId = '${spec.id}::${file.fileName}';
    final task = DownloadTask(
      taskId: taskId,
      url: url,
      filename: file.fileName,
      baseDirectory: BaseDirectory.applicationSupport,
      directory: 'models/${spec.subdir}',
      updates: Updates.statusAndProgress,
      retries: 3,
      allowPause: true,
    );
    final done = Completer<void>();
    final sub = FileDownloader().updates.listen((update) {
      if (update.task.taskId != taskId) return;
      if (update is TaskProgressUpdate && update.progress >= 0) {
        onFileProgress(update.progress);
      } else if (update is TaskStatusUpdate) {
        switch (update.status) {
          case TaskStatus.complete:
            if (!done.isCompleted) done.complete();
          case TaskStatus.failed:
          case TaskStatus.notFound:
          case TaskStatus.canceled:
            if (!done.isCompleted) {
              done.completeError(StateError('download ${update.status.name} for $url'));
            }
          default:
            break;
        }
      }
    });
    try {
      final ok = await FileDownloader().enqueue(task);
      if (!ok) throw StateError('failed to enqueue ${file.fileName}');
      await done.future;
    } finally {
      await sub.cancel();
    }
  }
```
Add `import 'dart:async';` if not present. (Adapt `TaskProgressUpdate`/`TaskStatusUpdate`/`enqueue` to the installed API. If a task is already enqueued/rescheduled from a prior run with the same `taskId`, `enqueue` returning false because it exists should be treated as "already running" — await its updates rather than failing; verify the 9.5.5 behavior and handle accordingly.)

- [ ] **Step 3: Verify build + ModelManager tests**

Run:
```bash
cd /Users/ali/Development/me/apps/privoice && melos run analyze
cd apps/mobile && flutter test test/model_manager_test.dart
cd apps/mobile && flutter build apk --debug
```
Expected: clean; tests green; APK built. (No unit test for the enqueue path — build + on-device are the gates.)

- [ ] **Step 4: Commit**

```bash
git add packages/models/lib/src/model_downloader.dart apps/mobile/lib/main.dart
git commit -m "feat: resumable downloads via enqueue + start()/trackTasks + stable task ids"
```

---

## Task 3: Honest notification + verification + STATUS + device

**Files:** Modify `apps/mobile/lib/main.dart`, `STATUS.md`.

- [ ] **Step 1: Fix the notification**

In `apps/mobile/lib/main.dart`, change `configureNotification` so it does NOT claim "Models ready" per file. Set the `complete`/`error` notifications to neutral per-file text (e.g. `complete: TaskNotification('Privoice', 'Download step complete')`) OR remove the `complete` notification and keep only `running` (progress) — the in-app Home banner is the source of truth for overall readiness. Keep `progressBar: true`.

- [ ] **Step 2: Whole-repo verification**

Run:
```bash
melos run analyze
melos run test
cd apps/mobile && flutter build apk --debug
```
Expected: analyze clean (6 packages); `melos run test` green; APK built.

- [ ] **Step 3: Update STATUS.md**

Update the "Model delivery" note: STT now downloads as 4 pre-extracted files (no in-app bz2 extraction — removes the on-device 6-min stall); downloads use `enqueue` + `start()`/`trackTasks` + stable task ids so they resume across process-death/swipe-away; notification no longer falsely says "ready". On-device Redmi verification of resume still the gate. Bump **Last updated**.

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/lib/main.dart STATUS.md
git commit -m "feat: honest download notification; docs(status): reliable download done"
```

- [ ] **Step 5: Build + push (controller) for on-device verification**

Controller builds + pushes the APK; user verifies on the Redmi: fresh install → smooth progress, **no extraction stall**; swipe app away mid-download + relaunch → **resumes** (not restart); "ready" only when both models installed.

---

## Self-Review Notes

- **Spec coverage:** extraction elimination + HF 4-file STT (Task 1) · resume via enqueue/start/trackTasks + stable ids (Task 2) · honest notification (Task 3) · verification + device (Tasks 1/3). Covered.
- **Type consistency:** `ModelFile{url,fileName,fallbackUrl,approxBytes}` (no `isTarBz2`); `ModelDownloader.install`/`isInstalled`/`pathTo` unchanged; `_downloadFile(file,spec,void Function(double))`; task id `'${spec.id}::${file.fileName}'`.
- **Placeholder scan:** none; "adapt to installed API" notes are deliberate for the version-sensitive plugin.
- **Sequencing:** Task 1 (the fix for the actually-observed extraction stall) lands independently; Task 2 (resume hardening) builds on it — if Task 2's enqueue wiring proves fiddly on-device, Task 1 already resolves the reported problem.
