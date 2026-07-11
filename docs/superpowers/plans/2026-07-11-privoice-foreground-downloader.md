# Foreground-Service Model Downloader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.
>
> **On-device feature:** the native download engine can't be unit-tested. The gate for the transport tasks is *the Android debug build compiles*; real verification is on the Redmi (the user). Only the onboarding change has a meaningful widget test.

**Goal:** Replace the in-process model-download transport with `background_downloader` so downloads run in an OS foreground service (progress notification, built-in resume) and survive the app being backgrounded / screen-locked / swiped away — keeping `ModelManager` and `ModelDownloader`'s public interface unchanged.

**Architecture:** `ModelDownloader.install` internals are rewritten over `background_downloader` (download → then the existing `compute(_extractTarBz2)`); its interface (`isInstalled`/`pathTo`/`install`) is unchanged, so `ModelManager` + `FakeModelDownloader` tests are untouched. Onboarding gains a 4th page priming `POST_NOTIFICATIONS`, requested on completion before `ensureDefaultSet`.

**Tech Stack:** Flutter, `background_downloader` (latest), Android foreground service + WorkManager.

## Global Constraints

- **`ModelDownloader` public interface unchanged:** `Future<bool> isInstalled(ModelSpec)`, `Future<String> pathTo(ModelSpec, String)`, `Future<void> install(ModelSpec, void Function(ModelInstallProgress))`, and `ModelInstallProgress{modelId,label,fraction,phase}` (phase strings `'Downloading…'|'Extracting…'|'Ready'`). Do NOT change these — `ModelManager` and its tests depend on them.
- **Files must land where `isInstalled` reads:** `PlatformPaths.subdir(spec.subdir)` = `getApplicationSupportDirectory()/models/<subdir>`. Target the plugin at `BaseDirectory.applicationSupport` + `directory: 'models/${spec.subdir}'` + `filename: file.fileName`. After download, assert the file exists at `pathTo(...)`; if the plugin's dir composition differs, switch to `BaseDirectory.root` with the absolute path. Invariant: file ends up at `pathTo(spec, file.fileName)`.
- **Preserve:** the source-fallback loop (`file.url` then `file.fallbackUrl`), the tar.bz2 extraction (`compute(_extractTarBz2, ...)` then delete the archive), the 4%-for-extraction progress ceiling on archive models, idempotent skip-if-installed, staged STT-then-LLM (that's `ModelManager`, untouched).
- **Keep** `ModelManager` (interface, state machine, wakelock) and the Home download banner unchanged.
- **Privacy:** no new network beyond existing model URLs; offline transcription stays network-free (privacy gate must pass).
- **Plugin API caveat:** use the API of the *installed* `background_downloader` version; the snippets below target the v8/v9 API and may need small adjustments (method names, `PermissionType`, `Updates`). Adapt to the version `pub add` installs; the build is the correctness gate.
- **Commands:**
  ```bash
  export PATH="/opt/homebrew/bin:$HOME/.pub-cache/bin:/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH"
  export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
  export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
  ```

---

## File Structure

- **Modify** `apps/mobile/pubspec.yaml` — add `background_downloader`.
- **Modify** `apps/mobile/android/app/src/main/AndroidManifest.xml` — `POST_NOTIFICATIONS` + foreground-service permissions/types per the plugin README.
- **Modify** `apps/mobile/lib/main.dart` — `FileDownloader().configureNotification(...)` at startup.
- **Rewrite** `packages/models/lib/src/model_downloader.dart` `install` internals (drop `http`/manual Range; keep extraction/isInstalled/pathTo). Add `background_downloader` to `packages/models/pubspec.yaml`.
- **Modify** `apps/mobile/lib/screens/onboarding_flow.dart` — 4th priming page.
- **Modify** `apps/mobile/lib/screens/app_bootstrap.dart` — request notification permission before `ensureDefaultSet` on completion.
- **Modify** `apps/mobile/test/screens/onboarding_flow_test.dart` — 4 pages.

---

## Task 1: Add the plugin, manifest, notification config, and rewrite ModelDownloader

**Files:**
- Modify: `packages/models/pubspec.yaml`, `apps/mobile/pubspec.yaml`, `apps/mobile/android/app/src/main/AndroidManifest.xml`, `apps/mobile/lib/main.dart`, `packages/models/lib/src/model_downloader.dart`

**Interfaces:**
- Consumes: `background_downloader` (`FileDownloader`, `DownloadTask`, `BaseDirectory`, `Updates`, `TaskStatus`, `TaskNotification`).
- Produces: unchanged `ModelDownloader` public surface.

- [ ] **Step 1: Add the dependency**

`cd packages/models && flutter pub add background_downloader` and `cd apps/mobile && flutter pub add background_downloader`. Run `flutter pub get` at the repo root (or `melos bootstrap` if configured). Note the resolved version.

- [ ] **Step 2: Android manifest**

In `apps/mobile/android/app/src/main/AndroidManifest.xml`, add inside `<manifest>` (per the installed `background_downloader` README — verify against it):
```xml
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
```
If the plugin's README for the installed version specifies a `<service>` entry or a different foreground-service type, use exactly what it says. (INTERNET is likely already present — don't duplicate.)

- [ ] **Step 3: Configure the notification at startup**

In `apps/mobile/lib/main.dart`, import `package:background_downloader/background_downloader.dart` and, in `main()` after `WidgetsFlutterBinding.ensureInitialized()`, add:
```dart
  FileDownloader().configureNotification(
    running: const TaskNotification('Downloading models', '{progress}'),
    complete: const TaskNotification('Models ready', 'Setup complete'),
    error: const TaskNotification('Download failed', 'Reopen Privoice to retry'),
    progressBar: true,
  );
```

- [ ] **Step 4: Rewrite `ModelDownloader.install` internals**

In `packages/models/lib/src/model_downloader.dart`: remove the `http` import and the `_downloadFile`/`_downloadFrom` manual-HTTP methods. Keep `ModelInstallProgress`, `isInstalled`, `pathTo`, `_p`, `_ExtractArgs`, `_extractTarBz2`. Add `import 'package:background_downloader/background_downloader.dart';`. Replace `install` + the download helper with:
```dart
  Future<void> install(
    ModelSpec spec,
    void Function(ModelInstallProgress) onProgress,
  ) async {
    if (await isInstalled(spec)) {
      onProgress(_p(spec, 1, 'Ready'));
      return;
    }
    final dir = await PlatformPaths.subdir(spec.subdir);
    for (final file in spec.files) {
      await _downloadFile(file, spec, onProgress);
      if (file.isTarBz2) {
        final dest = p.join(dir, file.fileName);
        onProgress(_p(spec, 0.96, 'Extracting…'));
        await compute(
          _extractTarBz2,
          _ExtractArgs(dest, dir, spec.expectedFiles),
        );
        await File(dest).delete();
      }
    }
    onProgress(_p(spec, 1, 'Ready'));
  }

  /// Try the primary URL, then the fallback mirror, via the OS download engine.
  Future<void> _downloadFile(
    ModelFile file,
    ModelSpec spec,
    void Function(ModelInstallProgress) onProgress,
  ) async {
    final urls = [file.url, if (file.fallbackUrl != null) file.fallbackUrl!];
    Object? lastError;
    for (final url in urls) {
      try {
        await _downloadFrom(url, file, spec, onProgress);
        // Verify it actually landed where isInstalled/pathTo look.
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
    void Function(ModelInstallProgress) onProgress,
  ) async {
    // Reserve the last 4% for extraction on archive models.
    final ceiling = spec.files.any((f) => f.isTarBz2) ? 0.95 : 1.0;
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
        if (progress >= 0) {
          onProgress(_p(spec, progress * ceiling, 'Downloading…'));
        }
      },
    );
    if (result.status != TaskStatus.complete) {
      throw StateError('download ${result.status.name} for $url');
    }
  }
```
(If the installed version's `download()` signature or `BaseDirectory.applicationSupport` path differs, adapt per Global Constraints — the invariant is the file at `pathTo(spec, file.fileName)`.)

- [ ] **Step 5: Verify it compiles (the gate for native code)**

Run:
```bash
cd apps/mobile && flutter analyze lib/main.dart
cd /Users/ali/Development/me/apps/privoice && melos run analyze
cd apps/mobile && flutter build apk --debug
```
Expected: analyze clean across packages; `✓ Built ... app-debug.apk` (this compiles the `background_downloader` native plugin — the real check that deps/manifest are correct).

- [ ] **Step 6: Confirm ModelManager tests still pass (interface unchanged)**

Run: `cd apps/mobile && flutter test test/model_manager_test.dart`
Expected: PASS unchanged (they use `FakeModelDownloader`, unaffected by the real transport swap).

- [ ] **Step 7: Commit**

```bash
git add packages/models/pubspec.yaml apps/mobile/pubspec.yaml pubspec.lock packages/models/pubspec.lock apps/mobile/android/app/src/main/AndroidManifest.xml apps/mobile/lib/main.dart packages/models/lib/src/model_downloader.dart
git commit -m "feat: foreground-service model download via background_downloader"
```
(Omit any lockfile paths that aren't tracked.)

---

## Task 2: Onboarding notification priming + permission request

**Files:**
- Modify: `apps/mobile/lib/screens/onboarding_flow.dart`, `apps/mobile/lib/screens/app_bootstrap.dart`
- Test: `apps/mobile/test/screens/onboarding_flow_test.dart`

**Interfaces:**
- Consumes: `background_downloader` (`FileDownloader().permissions`), existing `OnboardingFlow`/`AppBootstrap`.
- Produces: a 4-page onboarding; permission requested on completion before `ensureDefaultSet`.

- [ ] **Step 1: Update the onboarding widget test for 4 pages**

In `apps/mobile/test/screens/onboarding_flow_test.dart`, the "advances through pages" test currently taps `Next` twice to reach `Start`. Change it to tap `Next` **three** times (4 pages), then assert `Start` and that tapping it fires `onDone`. Keep the Skip test unchanged. (Update only the Next-tap count and any page-count assertion.)

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/mobile && flutter test test/screens/onboarding_flow_test.dart`
Expected: FAIL — only 3 pages exist, so after two `Next` taps `Start` already shows (or the third `Next` isn't found).

- [ ] **Step 3: Add the 4th onboarding page**

In `apps/mobile/lib/screens/onboarding_flow.dart`, append a 4th entry to the `_pages` list (after "Getting you set up"):
```dart
    _PageData(
      icon: Icons.notifications_active_outlined,
      title: 'Keep you posted',
      body: 'We’ll show a progress notification while your models download, so '
          'you can use other apps and it keeps going in the background. '
          'You can allow notifications on the next screen.',
    ),
```
(No other changes — the dots, Next/Start logic, and `onDone` already adapt to `_pages.length`.)

- [ ] **Step 4: Request notification permission on completion**

In `apps/mobile/lib/screens/app_bootstrap.dart`, add `import 'package:background_downloader/background_downloader.dart';` and, in `_finishOnboarding()`, request the permission before starting the download:
```dart
  Future<void> _finishOnboarding() async {
    await SettingsService.setOnboardingComplete(true);
    try {
      await FileDownloader().permissions.request(PermissionType.notifications);
    } catch (_) {
      // best-effort: download still runs via the foreground service if denied
    }
    _manager.ensureDefaultSet();
    if (mounted) setState(() => _onboarded = true);
  }
```
(If the installed version names this differently, adapt; denial/absence must be non-fatal.)

- [ ] **Step 5: Run tests + analyze**

Run:
```bash
cd apps/mobile && flutter test test/screens/onboarding_flow_test.dart test/screens/app_bootstrap_test.dart
cd apps/mobile && flutter analyze lib/screens/onboarding_flow.dart lib/screens/app_bootstrap.dart
```
Expected: PASS; analyze clean. (The `app_bootstrap_test` injects a ready manager and doesn't complete onboarding via `_finishOnboarding` with a real permission call — confirm it still passes; if a test drives `_finishOnboarding`, the permission call is wrapped in try/catch so a `MissingPluginException` in the test VM is swallowed.)

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/screens/onboarding_flow.dart apps/mobile/lib/screens/app_bootstrap.dart apps/mobile/test/screens/onboarding_flow_test.dart
git commit -m "feat: onboarding notification priming + request POST_NOTIFICATIONS"
```

---

## Task 3: Full verification + STATUS + device build

**Files:** Modify `STATUS.md`.

- [ ] **Step 1: Whole-repo analyze + tests + build**

Run:
```bash
export PATH="/opt/homebrew/bin:$HOME/.pub-cache/bin:/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH"
export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
melos run analyze
melos run test
cd apps/mobile && flutter build apk --debug
```
Expected: analyze clean (6 packages); `melos run test` green; debug APK built.

- [ ] **Step 2: Update STATUS.md**

Edit `STATUS.md` "Known gaps → Model delivery": mark the foreground-service downloader **done (code-complete, on-device pending)** — "downloads now run in an OS foreground service (background_downloader) with a progress notification; survive backgrounding/screen-off/swipe-away; resume built in. On-device verification on the Redmi outstanding." Note the R3 wakelock is now redundant but retained. Bump **Last updated**.

- [ ] **Step 3: Commit**

```bash
git add STATUS.md
git commit -m "docs(status): foreground-service downloader done (code-complete)"
```

- [ ] **Step 4: Build + push for on-device verification (controller does this)**

The controller builds and pushes the APK, then hands off to the user to verify on the Redmi: start a fresh download (clear the model files first), then **lock the screen / switch apps / swipe Privoice away** mid-download and confirm it continues (progress notification visible if allowed) and completes, and that features unlock when files land.

---

## Self-Review Notes

- **Spec coverage:** plugin + manifest + notification config (Task 1 Steps 1–3) · `ModelDownloader` transport rewrite preserving interface/extraction/fallback/path-invariant (Task 1 Step 4) · onboarding 4th page + permission priming (Task 2) · verification + STATUS + device handoff (Task 3). Covered.
- **Type consistency:** `ModelDownloader.install`/`isInstalled`/`pathTo`/`ModelInstallProgress` unchanged; `DownloadTask`/`FileDownloader`/`TaskStatus`/`PermissionType` from the plugin; `_pages`/`_PageData` extended in place.
- **Placeholder scan:** none — code is complete; the "adapt to installed version" notes are deliberate for a version-sensitive native plugin, not placeholders.
- **Testability honesty:** the native download path is build-verified + on-device-verified, not unit-tested — stated up front; `ModelManager`/onboarding tests remain the automated safety net.
