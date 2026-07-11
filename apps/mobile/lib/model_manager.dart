import 'package:flutter/foundation.dart';
import 'package:privoice_models/privoice_models.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

enum ModelPhase { notInstalled, downloading, extracting, ready, error }

/// Toggles a screen wakelock. Injected so tests can observe it without the
/// platform plugin.
typedef WakelockToggle = Future<void> Function(bool enable);

Future<void> _defaultWakelock(bool enable) =>
    enable ? WakelockPlus.enable() : WakelockPlus.disable();

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
  ModelManager({ModelDownloader? downloader, WakelockToggle? wakelock})
      : _dl = downloader ?? ModelDownloader(),
        _wakelock = wakelock ?? _defaultWakelock;

  /// App-wide instance used by the running app.
  static final ModelManager instance = ModelManager();

  final ModelDownloader _dl;
  final WakelockToggle _wakelock;
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
  ///
  /// Holds a screen wakelock while a download is in flight so the OS doesn't
  /// suspend the process (and drop the socket) when the screen would lock —
  /// the in-process download only survives while the app stays awake. The
  /// wakelock is acquired lazily (only if something actually needs
  /// downloading) and always released in the `finally`.
  Future<void> ensureDefaultSet() async {
    if (_running) return;
    _running = true;
    var wakelockHeld = false;
    try {
      for (final spec in ModelCatalog.defaultSet) {
        try {
          if (await _dl.isInstalled(spec)) {
            _set(spec, const ModelState(ModelPhase.ready, fraction: 1));
            continue;
          }
          if (!wakelockHeld) {
            wakelockHeld = true;
            await _toggleWakelock(true);
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
      if (wakelockHeld) await _toggleWakelock(false);
      _running = false;
    }
  }

  /// Best-effort wakelock toggle: a failure (unsupported platform, missing
  /// plugin, permission) must never abort or fail a download.
  Future<void> _toggleWakelock(bool enable) async {
    try {
      await _wakelock(enable);
    } catch (_) {
      // ignore — the wakelock is a nicety, not a requirement
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
