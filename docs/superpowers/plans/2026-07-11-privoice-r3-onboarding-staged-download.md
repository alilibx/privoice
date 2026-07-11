# R3 — Onboarding + Staged/Background Download Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hard first-launch download gate with a short 3-screen onboarding, then let the user into the app immediately while the default model set (STT Parakeet, then Llama 1B) downloads in the background and unlocks features per-model.

**Architecture:** A singleton `ModelManager` (`ChangeNotifier`) wraps the existing `ModelDownloader` (HTTP-Range resume reused as-is) and publishes per-model state (`notInstalled → downloading → extracting → ready → error`). A bootstrap widget in `main.dart` shows onboarding on first launch then `HomeScreen`, and calls `ModelManager.ensureDefaultSet()` to start/resume downloading. `HomeScreen` and `TranscriptScreen` listen to the manager to gate Record (on `sttReady`) and AI actions (on `llmReady`).

**Tech Stack:** Flutter, `ChangeNotifier`/`ListenableBuilder`, `shared_preferences`, existing `privoice_models` package. No new dependencies.

## Global Constraints

- **No new native dependency, no wakelock, no notification** — in-process resilient download only (reuse `ModelDownloader`).
- **Privacy invariant:** no network call in the offline transcription flow. `ModelManager` must NOT self-start; downloading begins only when `ensureDefaultSet()` is explicitly called. Tests must not hit the network.
- **Default set order:** STT first (`ModelCatalog.parakeetStt`), then LLM (`ModelCatalog.llama1b`) — from `ModelCatalog.defaultSet`.
- **Design tokens:** use existing R1 theme (`Theme.of(context).colorScheme`), no hard-coded colors. Follow existing file/style patterns (plain `ValueNotifier`/`setState`, no state-management lib).
- **Commands (prefix every build/test/analyze):**
  ```bash
  export PATH="/opt/homebrew/bin:$HOME/.pub-cache/bin:/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH"
  export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
  export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
  ```
  Run mobile tests from `apps/mobile` with `flutter test`; analyze the whole repo with `melos run analyze`.

---

## File Structure

- **Create** `apps/mobile/lib/model_manager.dart` — `ModelPhase`, `ModelState`, `ModelManager` (singleton state machine over `ModelDownloader`).
- **Create** `apps/mobile/lib/screens/onboarding_flow.dart` — 3-screen intro `PageView`, calls `onDone`.
- **Create** `apps/mobile/lib/screens/app_bootstrap.dart` — decides onboarding vs. home; kicks off `ensureDefaultSet()`.
- **Create** `apps/mobile/test/fakes/fake_model_downloader.dart` — shared test double for `ModelDownloader`.
- **Create** tests: `apps/mobile/test/model_manager_test.dart`, `apps/mobile/test/settings_test.dart`, `apps/mobile/test/screens/onboarding_flow_test.dart`, `apps/mobile/test/screens/app_bootstrap_test.dart`.
- **Modify** `apps/mobile/lib/settings.dart` — add `onboardingComplete` / `setOnboardingComplete`.
- **Modify** `apps/mobile/lib/main.dart` — replace `ModelGate` with `AppBootstrap`.
- **Modify** `apps/mobile/lib/screens/home_screen.dart` — download banner + Record-FAB gating (accept optional `ModelManager`).
- **Modify** `apps/mobile/lib/screens/transcript_screen.dart` — AI smart-action gating (accept optional `ModelManager`).
- **Modify** existing tests `home_screen_test.dart`, `transcript_screen_test.dart`, `privacy_gate_test.dart` — inject a ready manager.
- **Delete** `apps/mobile/lib/screens/model_gate.dart` — superseded. (`model_download_screen.dart` stays; still used by Settings 3B flow.)

---

## Task 1: `onboardingComplete` setting

**Files:**
- Modify: `apps/mobile/lib/settings.dart`
- Test: `apps/mobile/test/settings_test.dart` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `Future<bool> SettingsService.onboardingComplete()`, `Future<void> SettingsService.setOnboardingComplete(bool)`.

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/settings_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('onboardingComplete defaults to false, persists true', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await SettingsService.onboardingComplete(), isFalse);

    await SettingsService.setOnboardingComplete(true);
    expect(await SettingsService.onboardingComplete(), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/settings_test.dart`
Expected: FAIL — `onboardingComplete` / `setOnboardingComplete` not defined on `SettingsService`.

- [ ] **Step 3: Add the setting**

In `apps/mobile/lib/settings.dart`, add the key constant next to the others and two methods inside `SettingsService`:
```dart
  static const _kOnboardingComplete = 'onboarding_complete';

  static Future<bool> onboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboardingComplete) ?? false;
  }

  static Future<void> setOnboardingComplete(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingComplete, value);
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/settings_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/settings.dart apps/mobile/test/settings_test.dart
git commit -m "feat(r3): persist onboardingComplete setting"
```

---

## Task 2: `ModelManager` state machine

**Files:**
- Create: `apps/mobile/lib/model_manager.dart`
- Create: `apps/mobile/test/fakes/fake_model_downloader.dart`
- Test: `apps/mobile/test/model_manager_test.dart`

**Interfaces:**
- Consumes: `ModelDownloader`, `ModelInstallProgress`, `ModelSpec`, `ModelCatalog` (from `package:privoice_models/privoice_models.dart`).
- Produces:
  - `enum ModelPhase { notInstalled, downloading, extracting, ready, error }`
  - `class ModelState { final ModelPhase phase; final double fraction; final String? error; const ModelState(this.phase, {this.fraction = 0, this.error}); }`
  - `class ModelManager extends ChangeNotifier`:
    - `ModelManager({ModelDownloader? downloader})`
    - `static final ModelManager instance`
    - `ModelState stateOf(ModelSpec spec)`
    - `bool get sttReady` · `bool get llmReady` · `bool get allReady` · `bool get hasError`
    - `double get overallFraction`
    - `Future<void> ensureDefaultSet()`
    - `@visibleForTesting void markAllReadyForTest()`

- [ ] **Step 1: Write the shared fake downloader**

Create `apps/mobile/test/fakes/fake_model_downloader.dart`:
```dart
import 'package:privoice_models/privoice_models.dart';

/// Test double for [ModelDownloader]. Emits a mid-download then a ready
/// progress event; records install calls; can be told to fail specific ids.
class FakeModelDownloader extends ModelDownloader {
  FakeModelDownloader({
    Set<String> installed = const {},
    this.failIds = const {},
  }) : _installed = {...installed};

  final Set<String> _installed;
  final Set<String> failIds;
  final List<String> installCalls = [];

  @override
  Future<bool> isInstalled(ModelSpec spec) async => _installed.contains(spec.id);

  @override
  Future<void> install(
    ModelSpec spec,
    void Function(ModelInstallProgress) onProgress,
  ) async {
    installCalls.add(spec.id);
    onProgress(ModelInstallProgress(
        modelId: spec.id, label: spec.displayName, fraction: 0.5, phase: 'Downloading…'));
    if (failIds.contains(spec.id)) {
      throw StateError('fake failure ${spec.id}');
    }
    _installed.add(spec.id);
    onProgress(ModelInstallProgress(
        modelId: spec.id, label: spec.displayName, fraction: 1, phase: 'Ready'));
  }
}
```

- [ ] **Step 2: Write the failing test**

Create `apps/mobile/test/model_manager_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/model_manager.dart';
import 'package:privoice_models/privoice_models.dart';

import 'fakes/fake_model_downloader.dart';

void main() {
  final stt = ModelCatalog.parakeetStt;
  final llm = ModelCatalog.llama1b;

  test('starts notInstalled and not ready', () {
    final m = ModelManager(downloader: FakeModelDownloader());
    expect(m.stateOf(stt).phase, ModelPhase.notInstalled);
    expect(m.sttReady, isFalse);
    expect(m.llmReady, isFalse);
    expect(m.allReady, isFalse);
  });

  test('ensureDefaultSet downloads STT before LLM and ends ready', () async {
    final fake = FakeModelDownloader();
    final m = ModelManager(downloader: fake);
    await m.ensureDefaultSet();

    expect(fake.installCalls, [stt.id, llm.id]); // STT first
    expect(m.sttReady, isTrue);
    expect(m.llmReady, isTrue);
    expect(m.allReady, isTrue);
    expect(m.overallFraction, 1.0);
  });

  test('skips already-installed models (no re-download)', () async {
    final fake = FakeModelDownloader(installed: {stt.id, llm.id});
    final m = ModelManager(downloader: fake);
    await m.ensureDefaultSet();
    expect(fake.installCalls, isEmpty);
    expect(m.allReady, isTrue);
  });

  test('a failing model surfaces error; retry after fix succeeds', () async {
    final fake = FakeModelDownloader(failIds: {llm.id});
    final m = ModelManager(downloader: fake);
    await m.ensureDefaultSet();

    expect(m.sttReady, isTrue);
    expect(m.stateOf(llm).phase, ModelPhase.error);
    expect(m.hasError, isTrue);

    fake.failIds.clear();
    await m.ensureDefaultSet(); // retry
    expect(m.llmReady, isTrue);
    expect(m.hasError, isFalse);
  });

  test('notifies listeners on progress', () async {
    final m = ModelManager(downloader: FakeModelDownloader());
    var notes = 0;
    m.addListener(() => notes++);
    await m.ensureDefaultSet();
    expect(notes, greaterThan(0));
  });

  test('markAllReadyForTest flips readiness without downloading', () {
    final fake = FakeModelDownloader();
    final m = ModelManager(downloader: fake)..markAllReadyForTest();
    expect(m.allReady, isTrue);
    expect(fake.installCalls, isEmpty);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/model_manager_test.dart`
Expected: FAIL — `model_manager.dart` does not exist.

- [ ] **Step 4: Implement `ModelManager`**

Create `apps/mobile/lib/model_manager.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'package:privoice_models/privoice_models.dart';

enum ModelPhase { notInstalled, downloading, extracting, ready, error }

/// Immutable per-model status.
class ModelState {
  const ModelState(this.phase, {this.fraction = 0, this.error});
  final ModelPhase phase;
  final double fraction; // 0..1
  final String? error;
}

/// Owns the background download of the default model set and publishes
/// per-model progress. Never self-starts: downloading begins only when
/// [ensureDefaultSet] is called (privacy: offline flows stay network-free).
class ModelManager extends ChangeNotifier {
  ModelManager({ModelDownloader? downloader})
      : _dl = downloader ?? ModelDownloader();

  /// App-wide instance used by the running app.
  static final ModelManager instance = ModelManager();

  final ModelDownloader _dl;
  final Map<String, ModelState> _states = {};
  bool _running = false;

  ModelState stateOf(ModelSpec spec) =>
      _states[spec.id] ?? const ModelState(ModelPhase.notInstalled);

  bool _isReady(ModelSpec s) => stateOf(s).phase == ModelPhase.ready;

  bool get sttReady => _isReady(ModelCatalog.parakeetStt);
  bool get llmReady => _isReady(ModelCatalog.llama1b);
  bool get allReady => ModelCatalog.defaultSet.every(_isReady);
  bool get hasError =>
      _states.values.any((s) => s.phase == ModelPhase.error);

  double get overallFraction {
    final specs = ModelCatalog.defaultSet;
    if (specs.isEmpty) return 1;
    final sum = specs.fold<double>(0, (a, s) {
      final st = stateOf(s);
      return a + (st.phase == ModelPhase.ready ? 1.0 : st.fraction);
    });
    return sum / specs.length;
  }

  /// Download/resume every not-yet-installed default model, STT first.
  /// Idempotent and safe to call repeatedly; a call while running is a no-op.
  Future<void> ensureDefaultSet() async {
    if (_running) return;
    _running = true;
    try {
      for (final spec in ModelCatalog.defaultSet) {
        try {
          if (await _dl.isInstalled(spec)) {
            _set(spec, const ModelState(ModelPhase.ready, fraction: 1));
            continue;
          }
          await _dl.install(spec, (p) {
            final phase = p.phase == 'Extracting…'
                ? ModelPhase.extracting
                : ModelPhase.downloading;
            _set(spec, ModelState(phase, fraction: p.fraction));
          });
          _set(spec, const ModelState(ModelPhase.ready, fraction: 1));
        } catch (e) {
          _set(spec, ModelState(ModelPhase.error, error: '$e'));
          break; // stop the chain; Retry restarts from here (resumes bytes)
        }
      }
    } finally {
      _running = false;
    }
  }

  void _set(ModelSpec spec, ModelState state) {
    _states[spec.id] = state;
    notifyListeners();
  }

  @visibleForTesting
  void markAllReadyForTest() {
    for (final s in ModelCatalog.defaultSet) {
      _states[s.id] = const ModelState(ModelPhase.ready, fraction: 1);
    }
    notifyListeners();
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/model_manager_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/model_manager.dart apps/mobile/test/model_manager_test.dart apps/mobile/test/fakes/fake_model_downloader.dart
git commit -m "feat(r3): ModelManager background staged-download state machine"
```

---

## Task 3: Onboarding flow (3 screens)

**Files:**
- Create: `apps/mobile/lib/screens/onboarding_flow.dart`
- Test: `apps/mobile/test/screens/onboarding_flow_test.dart`

**Interfaces:**
- Consumes: nothing (pure UI).
- Produces: `class OnboardingFlow extends StatefulWidget { const OnboardingFlow({super.key, required this.onDone}); final VoidCallback onDone; }`. The final page's **Start** button (and the **Skip** action) call `onDone`.

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/screens/onboarding_flow_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/onboarding_flow.dart';

void main() {
  testWidgets('advances through pages and Start fires onDone', (tester) async {
    var done = false;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingFlow(onDone: () => done = true),
    ));
    await tester.pumpAndSettle();

    // Page 1: welcome, Next visible, Start not yet.
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Start'), findsNothing);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Page 3: Start visible.
    expect(find.text('Start'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
  });

  testWidgets('Skip fires onDone immediately', (tester) async {
    var done = false;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingFlow(onDone: () => done = true),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/screens/onboarding_flow_test.dart`
Expected: FAIL — `onboarding_flow.dart` does not exist.

- [ ] **Step 3: Implement `OnboardingFlow`**

Create `apps/mobile/lib/screens/onboarding_flow.dart`:
```dart
import 'package:flutter/material.dart';

/// First-launch intro: 3 swipeable screens. The final page commits via [onDone]
/// (also reachable via Skip). Uses the app's R1 theme tokens.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = <_PageData>[
    _PageData(
      icon: Icons.graphic_eq_rounded,
      title: 'Capture every meeting',
      body: 'Record, transcribe, and summarize meetings into clean minutes '
          'and action items — all in one place.',
    ),
    _PageData(
      icon: Icons.lock_outline_rounded,
      title: 'Private by design',
      body: 'Speech-to-text and AI run entirely on your phone. Nothing is '
          'uploaded — your conversations never leave the device.',
    ),
    _PageData(
      icon: Icons.download_for_offline_outlined,
      title: 'Getting you set up',
      body: 'We’re downloading your on-device models (about 1.5 GB). You can '
          'start exploring now — best on Wi-Fi.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _page == _pages.length - 1;

  void _next() {
    if (_isLast) {
      widget.onDone();
    } else {
      _controller.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton(
                  onPressed: widget.onDone,
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _Page(data: _pages[i]),
              ),
            ),
            _Dots(count: _pages.length, index: _page, color: scheme.primary),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(_isLast ? 'Start' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageData {
  const _PageData({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;
}

class _Page extends StatelessWidget {
  const _Page({required this.data});
  final _PageData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(data.icon, size: 84, color: scheme.primary),
          const SizedBox(height: 32),
          Text(data.title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Text(data.body,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5)),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index, required this.color});
  final int count;
  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == index ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == index ? color : color.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/screens/onboarding_flow_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/screens/onboarding_flow.dart apps/mobile/test/screens/onboarding_flow_test.dart
git commit -m "feat(r3): 3-screen onboarding flow"
```

---

## Task 4: `AppBootstrap` — wire onboarding + background download; retire `ModelGate`

**Files:**
- Create: `apps/mobile/lib/screens/app_bootstrap.dart`
- Modify: `apps/mobile/lib/main.dart`
- Delete: `apps/mobile/lib/screens/model_gate.dart`
- Test: `apps/mobile/test/screens/app_bootstrap_test.dart`

**Interfaces:**
- Consumes: `SettingsService.onboardingComplete` / `setOnboardingComplete` (Task 1); `ModelManager` (Task 2); `OnboardingFlow` (Task 3); existing `HomeScreen`.
- Produces: `class AppBootstrap extends StatefulWidget` with constructor `AppBootstrap({super.key, required MeetingRepository repository, required AiService ai, required ValueNotifier<ThemeMode> themeMode, ModelManager? modelManager})`. When `modelManager` is null it uses `ModelManager.instance`.

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/screens/app_bootstrap_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/ai_service.dart';
import 'package:mobile/model_manager.dart';
import 'package:mobile/screens/app_bootstrap.dart';
import 'package:privoice_core/privoice_core.dart';
import 'package:privoice_models/privoice_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_ai_engine.dart';
import '../fakes/fake_meeting_repository.dart';
import '../fakes/fake_model_downloader.dart';

ModelManager _readyManager() => ModelManager(
      downloader: FakeModelDownloader(installed: {
        ModelCatalog.parakeetStt.id,
        ModelCatalog.llama1b.id,
      }),
    );

Widget _boot(ModelManager m) => MaterialApp(
      home: AppBootstrap(
        repository: FakeMeetingRepository(),
        ai: AiService(engine: FakeAiEngine()),
        themeMode: ValueNotifier(ThemeMode.system),
        modelManager: m,
      ),
    );

void main() {
  testWidgets('first launch shows onboarding', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_boot(_readyManager()));
    await tester.pumpAndSettle();

    expect(find.text('Capture every meeting'), findsOneWidget); // page 1 visible
    expect(find.text('Skip'), findsOneWidget); // onboarding chrome present
    expect(find.text('On-device'), findsNothing); // not in the app yet
  });

  testWidgets('completing onboarding reveals home and starts download',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final m = _readyManager();
    await tester.pumpWidget(_boot(m));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('On-device'), findsOneWidget); // HomeScreen app-bar badge
    expect(m.allReady, isTrue); // ensureDefaultSet ran against installed fakes
  });

  testWidgets('returning user goes straight to home', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    await tester.pumpWidget(_boot(_readyManager()));
    await tester.pumpAndSettle();

    expect(find.text('Skip'), findsNothing);
    expect(find.text('On-device'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/screens/app_bootstrap_test.dart`
Expected: FAIL — `app_bootstrap.dart` does not exist.

- [ ] **Step 3: Implement `AppBootstrap`**

Create `apps/mobile/lib/screens/app_bootstrap.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:privoice_core/privoice_core.dart';

import '../ai_service.dart';
import '../model_manager.dart';
import '../settings.dart';
import 'home_screen.dart';
import 'onboarding_flow.dart';

/// First-launch router: onboarding until complete, then the app. Kicks off the
/// background model download (resumes any partial install on later launches).
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({
    super.key,
    required this.repository,
    required this.ai,
    required this.themeMode,
    this.modelManager,
  });

  final MeetingRepository repository;
  final AiService ai;
  final ValueNotifier<ThemeMode> themeMode;
  final ModelManager? modelManager;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  bool? _onboarded;

  ModelManager get _manager => widget.modelManager ?? ModelManager.instance;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final done = await SettingsService.onboardingComplete();
    if (done) _manager.ensureDefaultSet(); // fire-and-forget resume
    if (mounted) setState(() => _onboarded = done);
  }

  Future<void> _finishOnboarding() async {
    await SettingsService.setOnboardingComplete(true);
    _manager.ensureDefaultSet(); // fire-and-forget start
    if (mounted) setState(() => _onboarded = true);
  }

  @override
  Widget build(BuildContext context) {
    final onboarded = _onboarded;
    if (onboarded == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!onboarded) {
      return OnboardingFlow(onDone: _finishOnboarding);
    }
    return HomeScreen(
      repository: widget.repository,
      ai: widget.ai,
      themeMode: widget.themeMode,
      modelManager: _manager,
    );
  }
}
```

- [ ] **Step 4: Add the (ignored-for-now) `modelManager` param to `HomeScreen`**

`AppBootstrap` (Step 3) passes `modelManager:` into the `HomeScreen(...)` call, so `HomeScreen` needs the optional param before anything compiles. In `apps/mobile/lib/screens/home_screen.dart`, add `import '../model_manager.dart';` at the top, then add to the constructor:
```dart
    this.modelManager,
```
and as a field:
```dart
  final ModelManager? modelManager;
```
(Behavior stays unchanged here; it's wired in Task 5.)

- [ ] **Step 5: Wire it into `main.dart` and delete `ModelGate`**

In `apps/mobile/lib/main.dart`: replace the `import 'screens/model_gate.dart';` line with `import 'screens/app_bootstrap.dart';`, and replace the `home:` widget:
```dart
        home: AppBootstrap(
          repository: repository,
          ai: ai,
          themeMode: themeMode,
        ),
```
Then delete the superseded gate:
```bash
git rm apps/mobile/lib/screens/model_gate.dart
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd apps/mobile && flutter test test/screens/app_bootstrap_test.dart test/screens/home_screen_test.dart`
Expected: PASS (3 bootstrap tests; existing home tests unaffected — they don't pass a manager).

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/screens/app_bootstrap.dart apps/mobile/lib/main.dart apps/mobile/lib/screens/home_screen.dart apps/mobile/test/screens/app_bootstrap_test.dart
git rm apps/mobile/lib/screens/model_gate.dart
git commit -m "feat(r3): AppBootstrap wires onboarding + background download; retire ModelGate"
```

---

## Task 5: Home — download banner + Record-FAB gating

**Files:**
- Modify: `apps/mobile/lib/screens/home_screen.dart`
- Modify: `apps/mobile/test/screens/home_screen_test.dart`
- Modify: `apps/mobile/test/privacy_gate_test.dart`
- Test: add cases to `apps/mobile/test/screens/home_screen_test.dart`

**Interfaces:**
- Consumes: `ModelManager` (`sttReady`, `overallFraction`, `allReady`, `hasError`, `stateOf`, `ensureDefaultSet`) from Task 2; `modelManager` param added to `HomeScreen` in Task 4.
- Produces: gated Record FAB + a `_DownloadBanner` above the list. No new public API.

- [ ] **Step 1: Write the failing tests (gating behavior)**

Add to `apps/mobile/test/screens/home_screen_test.dart` — new imports at top:
```dart
import 'package:mobile/model_manager.dart';
import 'package:privoice_models/privoice_models.dart';
import '../fakes/fake_model_downloader.dart';
```
Helper + tests (append inside `main()`):
```dart
  ModelManager _readyManager() => ModelManager(
        downloader: FakeModelDownloader(installed: {
          ModelCatalog.parakeetStt.id,
          ModelCatalog.llama1b.id,
        }),
      )..markAllReadyForTest();

  testWidgets('shows setup banner while models not ready', (tester) async {
    final m = ModelManager(downloader: FakeModelDownloader()); // nothing ready
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        repository: FakeMeetingRepository(),
        ai: AiService(),
        themeMode: ValueNotifier(ThemeMode.system),
        modelManager: m,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Setting up'), findsOneWidget);
  });

  testWidgets('tapping Record while STT not ready shows a snackbar, no push',
      (tester) async {
    final m = ModelManager(downloader: FakeModelDownloader());
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        repository: FakeMeetingRepository(),
        ai: AiService(),
        themeMode: ValueNotifier(ThemeMode.system),
        modelManager: m,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(); // let the snackbar appear
    expect(find.textContaining('Speech-to-text'), findsOneWidget);
  });

  testWidgets('no banner when all models ready', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        repository: FakeMeetingRepository(),
        ai: AiService(),
        themeMode: ValueNotifier(ThemeMode.system),
        modelManager: _readyManager(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Setting up'), findsNothing);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/mobile && flutter test test/screens/home_screen_test.dart`
Expected: FAIL — no banner widget; Record FAB always pushes.

- [ ] **Step 3: Implement banner + gating in `HomeScreen`**

In `apps/mobile/lib/screens/home_screen.dart`:

(a) Resolve the manager and rebuild on its changes. Add a getter in `_HomeScreenState`:
```dart
  ModelManager get _manager => widget.modelManager ?? ModelManager.instance;
```

(b) Gate `_record()`:
```dart
  Future<void> _record() async {
    if (!_manager.sttReady) {
      final pct = (_manager.stateOf(ModelCatalog.parakeetStt).fraction * 100)
          .round();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Speech-to-text is still downloading ($pct%)'),
      ));
      return;
    }
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecordScreen(repository: widget.repository),
      ),
    );
    if (saved == true) _load();
  }
```
Add imports at top: `import 'package:privoice_models/privoice_models.dart';` (for `ModelCatalog`). `import '../model_manager.dart';` was added in Task 4.

(c) Wrap the whole `Scaffold` returned by `build` in a `ListenableBuilder` so banner + FAB reflect manager state. Change the start of `build`:
```dart
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _manager,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // ... existing body of the old build() continues unchanged ...
```
(Rename the old `build` body to `_buildScaffold`; keep every line inside it as-is except the two edits below.)

(d) Make the FAB reflect readiness (keep the label "Record" so it stays findable):
```dart
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _record,
        backgroundColor: _manager.sttReady ? null : scheme.surfaceContainerHighest,
        icon: _manager.sttReady
            ? const Icon(Icons.mic_rounded)
            : const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
        label: const Text('Record'),
      ),
```

(e) Insert the banner at the top of the body. Wrap the existing `body:` content so the banner sits above it. Replace `body: _loading ? ... : RefreshIndicator(...)` with:
```dart
      body: Column(
        children: [
          if (!_manager.allReady)
            _DownloadBanner(
              fraction: _manager.overallFraction,
              hasError: _manager.hasError,
              onRetry: _manager.ensureDefaultSet,
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _visible.isEmpty
                        ? _EmptyState(scheme: scheme, searching: _query.isNotEmpty)
                        : ListView.separated(
                            /* ... existing list, unchanged ... */
                          ),
                  ),
          ),
        ],
      ),
```
(Keep the existing `ListView.separated(...)` contents verbatim.)

(f) Add the banner widget at the bottom of the file:
```dart
class _DownloadBanner extends StatelessWidget {
  const _DownloadBanner({
    required this.fraction,
    required this.hasError,
    required this.onRetry,
  });
  final double fraction;
  final bool hasError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          Icon(hasError ? Icons.cloud_off_rounded : Icons.download_rounded,
              size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasError
                      ? 'Download paused'
                      : 'Setting up Privoice · ${(fraction * 100).round()}%',
                  style: TextStyle(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
                if (!hasError) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                        value: fraction > 0 ? fraction : null, minHeight: 5),
                  ),
                ],
              ],
            ),
          ),
          if (hasError)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Update existing tests to inject a ready manager**

The existing three home tests tap search / assert on 'Record' with the default (real) manager — they still pass because the default instance is never downloaded and the FAB label stays "Record". No change needed there.

In `apps/mobile/test/privacy_gate_test.dart`, the flow taps Summarize; inject a ready manager so the AI action stays enabled (Task 6 gates it on `llmReady`). Add imports:
```dart
import 'package:mobile/model_manager.dart';
import 'package:privoice_models/privoice_models.dart';
import 'fakes/fake_model_downloader.dart';
```
and pass to `HomeScreen(...)`:
```dart
        modelManager: ModelManager(
          downloader: FakeModelDownloader(installed: {
            ModelCatalog.parakeetStt.id,
            ModelCatalog.llama1b.id,
          }),
        )..markAllReadyForTest(),
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd apps/mobile && flutter test test/screens/home_screen_test.dart test/privacy_gate_test.dart`
Expected: PASS (existing + 3 new home tests; privacy gate still 0 HTTP clients).

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/screens/home_screen.dart apps/mobile/test/screens/home_screen_test.dart apps/mobile/test/privacy_gate_test.dart
git commit -m "feat(r3): Home download banner + Record gated on STT readiness"
```

---

## Task 6: Transcript — AI smart-action gating

**Files:**
- Modify: `apps/mobile/lib/screens/transcript_screen.dart`
- Modify: `apps/mobile/test/screens/transcript_screen_test.dart`

**Interfaces:**
- Consumes: `ModelManager.llmReady` (Task 2).
- Produces: `TranscriptScreen` gains optional `ModelManager? modelManager` (default `ModelManager.instance`); smart-action buttons disabled + "Preparing AI…" hint until `llmReady`.

- [ ] **Step 1: Write the failing test**

Add to `apps/mobile/test/screens/transcript_screen_test.dart` — imports:
```dart
import 'package:mobile/model_manager.dart';
import 'package:privoice_models/privoice_models.dart';
import '../fakes/fake_model_downloader.dart';
```
New test inside `main()`:
```dart
  testWidgets('AI actions disabled with hint until LLM ready', (tester) async {
    final meeting = Meeting(
      id: 1,
      title: 'Product sync',
      createdAt: DateTime(2026, 7, 10),
      audioPath: '',
      durationMs: 60000,
      transcript: 'Alice: ship the beta Friday.',
    );
    await tester.pumpWidget(MaterialApp(
      home: TranscriptScreen(
        meeting: meeting,
        repository: FakeMeetingRepository([meeting]),
        ai: AiService(engine: FakeAiEngine()),
        modelManager: ModelManager(downloader: FakeModelDownloader()), // not ready
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Preparing AI…'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(of: find.text('Summarize'), matching: find.byType(FilledButton)),
    );
    expect(button.onPressed, isNull); // disabled
  });
```
Also update the two existing transcript tests to pass a ready manager so their taps still work — add to each `TranscriptScreen(...)`:
```dart
        modelManager: ModelManager(
          downloader: FakeModelDownloader(installed: {
            ModelCatalog.parakeetStt.id,
            ModelCatalog.llama1b.id,
          }),
        )..markAllReadyForTest(),
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/mobile && flutter test test/screens/transcript_screen_test.dart`
Expected: FAIL — `TranscriptScreen` has no `modelManager` param; no "Preparing AI…" text.

- [ ] **Step 3: Implement gating in `TranscriptScreen`**

In `apps/mobile/lib/screens/transcript_screen.dart`:

(a) Add import + constructor param + field:
```dart
import '../model_manager.dart';
```
In the constructor add `this.modelManager,` and as a field:
```dart
  final ModelManager? modelManager;
```

(b) In `_TranscriptScreenState`, add:
```dart
  ModelManager get _manager => widget.modelManager ?? ModelManager.instance;
```

(c) Wrap the smart-action bar so it reacts to manager changes and passes readiness. Replace the `_SmartActionBar(...)` usage in `build` with a `ListenableBuilder`:
```dart
          ListenableBuilder(
            listenable: _manager,
            builder: (context, _) => _SmartActionBar(
              busy: _busy,
              aiReady: _manager.llmReady,
              onSummarize: _summarize,
              onActionItems: _actionItems,
              onAsk: _ask,
            ),
          ),
```

(d) Extend `_SmartActionBar` to take `aiReady` and show the hint / disable buttons:
```dart
class _SmartActionBar extends StatelessWidget {
  const _SmartActionBar({
    required this.busy,
    required this.aiReady,
    required this.onSummarize,
    required this.onActionItems,
    required this.onAsk,
  });

  final bool busy;
  final bool aiReady;
  final VoidCallback onSummarize;
  final VoidCallback onActionItems;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = aiReady && !busy;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!aiReady)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Row(children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: scheme.primary),
                ),
                const SizedBox(width: 8),
                Text('Preparing AI…',
                    style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ]),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _SmartButton(
                    icon: Icons.auto_awesome,
                    label: 'Summarize',
                    onTap: enabled ? onSummarize : null),
                const SizedBox(width: 8),
                _SmartButton(
                    icon: Icons.checklist_rounded,
                    label: 'Action items',
                    onTap: enabled ? onActionItems : null),
                const SizedBox(width: 8),
                _SmartButton(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Ask',
                    onTap: enabled ? onAsk : null),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```
(`_SmartButton` already renders as disabled when `onTap == null` — no change needed.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd apps/mobile && flutter test test/screens/transcript_screen_test.dart`
Expected: PASS (existing 2 updated + 1 new).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/screens/transcript_screen.dart apps/mobile/test/screens/transcript_screen_test.dart
git commit -m "feat(r3): gate transcript AI actions on LLM readiness"
```

---

## Task 7: Full verification + STATUS.md update

**Files:**
- Modify: `STATUS.md`

**Interfaces:** none.

- [ ] **Step 1: Analyze the whole repo**

Run:
```bash
export PATH="/opt/homebrew/bin:$HOME/.pub-cache/bin:/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH"
export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
melos run analyze
```
Expected: "No issues found!" for every package. Fix any analyzer error before continuing.

- [ ] **Step 2: Run the full mobile test suite**

Run: `cd apps/mobile && flutter test`
Expected: all tests PASS (previous suite + new settings/model_manager/onboarding/app_bootstrap/home/transcript tests).

- [ ] **Step 3: Debug build (native compile still works)**

Run: `cd apps/mobile && flutter build apk --debug`
Expected: `Built build/app/outputs/flutter-apk/app-debug.apk`.

- [ ] **Step 4: Update STATUS.md**

Edit `STATUS.md`:
- In the **Redesign (R1–R7)** line, flip `R3 onboarding + staged/background download ⬜` to `✅` (note: "3-screen onboarding + in-process background download via ModelManager; Record unlocks on STT, AI on LLM; ModelGate retired").
- In the **Now:** line, add R3 to the done list.
- Bump **Last updated** to `2026-07-11`.
- Under **Known gaps / tech debt**, update the "Model delivery" bullet to note in-app staged download now covers first launch; the OS foreground-service upgrade remains a possible follow-up if device testing shows aggressive process-kill.

Then verify on-device (per CLAUDE.md device workflow) before marking ✅ *verified*: sideload the debug APK to the Redmi 15C, confirm the onboarding shows on a fresh install, the app opens with the banner, and Record unlocks once STT lands. (If a device isn't available in this session, mark R3 code-complete and leave the on-device check as the outstanding item.)

- [ ] **Step 5: Commit**

```bash
git add STATUS.md
git commit -m "docs(status): R3 onboarding + staged/background download done"
```

---

## Self-Review Notes

- **Spec coverage:** Flow/entry (Task 4) · `ModelManager` (Task 2) · onboarding 3 screens (Task 3) · Home banner + Record gating (Task 5) · AI action gating (Task 6) · `onboardingComplete` setting (Task 1) · error/Retry (Task 2 state + Task 5 banner) · testing (each task's tests + Task 7 regression) · Settings 3B untouched (not modified) · no wakelock/no new deps (ModelManager uses `ModelDownloader` only). All covered.
- **Type consistency:** `ModelManager({ModelDownloader? downloader})`, `ensureDefaultSet()`, `stateOf`, `sttReady`/`llmReady`/`allReady`/`hasError`/`overallFraction`, `markAllReadyForTest()`, `ModelPhase`/`ModelState`, `FakeModelDownloader({installed, failIds})`, `AppBootstrap({..., modelManager})`, `HomeScreen({..., modelManager})`, `TranscriptScreen({..., modelManager})`, `OnboardingFlow({onDone})` used consistently across tasks.
- **Placeholder scan:** none — every code step shows full code.
