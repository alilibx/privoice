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

  ModelInstallProgress _p(ModelSpec s, double f, String phase) =>
      ModelInstallProgress(
          modelId: s.id, label: s.displayName, fraction: f.clamp(0, 1), phase: phase);
}
