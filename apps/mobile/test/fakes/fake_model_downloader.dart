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
