import 'dart:io';

import 'package:archive/archive.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
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
  final String phase; // 'Downloading…' | 'Extracting…' | 'Ready'
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

  ModelInstallProgress _p(ModelSpec s, double f, String phase) =>
      ModelInstallProgress(
          modelId: s.id, label: s.displayName, fraction: f.clamp(0, 1), phase: phase);
}

class _ExtractArgs {
  const _ExtractArgs(this.archivePath, this.destDir, this.expected);
  final String archivePath;
  final String destDir;
  final List<String> expected;
}

/// Runs in a background isolate: bunzip2 + untar, writing only the expected
/// files (flattened) into destDir.
void _extractTarBz2(_ExtractArgs args) {
  final compressed = File(args.archivePath).readAsBytesSync();
  final tarBytes = BZip2Decoder().decodeBytes(compressed);
  final archive = TarDecoder().decodeBytes(tarBytes);
  for (final entry in archive) {
    if (!entry.isFile) continue;
    final base = p.basename(entry.name);
    if (args.expected.contains(base)) {
      File(p.join(args.destDir, base)).writeAsBytesSync(entry.content as List<int>);
    }
  }
}
