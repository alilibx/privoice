import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:path/path.dart' as p;

import 'model_spec.dart';
import 'platform_paths.dart';

/// Progress for a single model install.
class ModelInstallProgress {
  const ModelInstallProgress({
    required this.modelId,
    required this.label,
    required this.fraction,
    required this.phase,
  });

  final String modelId;
  final String label;
  final double fraction; // 0..1
  final String phase; // 'Downloading…' | 'Ready'
}

class ModelDownloader {
  /// FileDownloader().updates is single-subscription; wrap it once as a
  /// broadcast stream so every download (and concurrent installs) can listen.
  static final Stream<TaskUpdate> _updates =
      FileDownloader().updates.asBroadcastStream();

  /// True when every expected file for [spec] is present on disk.
  Future<bool> isInstalled(ModelSpec spec) async {
    final dir = await PlatformPaths.subdir(spec.subdir);
    return spec.expectedFiles
        .every((f) => File(p.join(dir, f)).existsSync());
  }

  /// Absolute path to a file that belongs to [spec].
  Future<String> pathTo(ModelSpec spec, String fileName) async {
    final dir = await PlatformPaths.subdir(spec.subdir);
    return p.join(dir, fileName);
  }

  /// Download + install [spec], reporting progress. Idempotent: skips if ready.
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

  /// Try the primary URL, then the fallback mirror, via the OS download engine.
  Future<void> _downloadFile(
    ModelFile file,
    ModelSpec spec,
    void Function(double fileFraction) onFileProgress,
  ) async {
    // Already fully downloaded (e.g. by a prior run resumed on relaunch)?
    // background_downloader only writes the final path on completion, so a
    // present final file means done — skip re-downloading and never wait on
    // an updates event that already fired.
    if (File(await pathTo(spec, file.fileName)).existsSync()) {
      onFileProgress(1.0);
      return;
    }
    final urls = [file.url, if (file.fallbackUrl != null) file.fallbackUrl!];
    Object? lastError;
    for (final url in urls) {
      try {
        await _downloadFrom(url, file, spec, onFileProgress);
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

  /// Enqueues (rather than awaits) the download under a **stable** task id
  /// derived from [spec] + [file], so a relaunch after process death
  /// re-attaches to the same task instead of restarting it. Completion is
  /// observed via the shared `FileDownloader().updates` stream instead of
  /// the convenience `download()` future, because `download()` always mints
  /// a fresh task id and therefore cannot resume a task the OS rescheduled
  /// on launch (see `FileDownloader().start()` in main.dart).
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
    final sub = _updates.listen((update) {
      if (update.task.taskId != taskId) return;
      if (update is TaskProgressUpdate) {
        if (update.progress >= 0) onFileProgress(update.progress);
      } else if (update is TaskStatusUpdate) {
        switch (update.status) {
          case TaskStatus.complete:
            if (!done.isCompleted) done.complete();
          case TaskStatus.failed:
          case TaskStatus.notFound:
          case TaskStatus.canceled:
            if (!done.isCompleted) {
              done.completeError(
                  StateError('download ${update.status.name} for $url'));
            }
          default:
            break;
        }
      }
    });
    try {
      // A task with this stable id may already be active — e.g. rescheduled
      // by `FileDownloader().start(doRescheduleKilledTasks: true)` after a
      // process-death relaunch, or already running from an earlier call in
      // this same session (the primary/fallback retry loop in
      // `_downloadFile` reuses this taskId across attempts). 9.5.5's Android
      // implementation does NOT dedupe `enqueue()` by taskId — WorkManager
      // would simply start a second parallel job with the same tag — so we
      // must check first rather than rely on `enqueue()` returning false.
      final existing = await FileDownloader().taskForId(taskId);
      if (existing == null) {
        final ok = await FileDownloader().enqueue(task);
        if (!ok) {
          throw StateError('failed to enqueue ${file.fileName}');
        }
      }
      await done.future;
    } finally {
      await sub.cancel();
    }
  }

  ModelInstallProgress _p(ModelSpec s, double f, String phase) =>
      ModelInstallProgress(
          modelId: s.id, label: s.displayName, fraction: f.clamp(0, 1), phase: phase);
}
