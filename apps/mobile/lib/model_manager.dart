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
