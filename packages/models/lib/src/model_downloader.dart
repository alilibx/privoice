import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
      final dest = p.join(dir, file.fileName);
      await _downloadFile(file.url, dest, spec, onProgress);

      if (file.isTarBz2) {
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

  Future<void> _downloadFile(
    String url,
    String dest,
    ModelSpec spec,
    void Function(ModelInstallProgress) onProgress,
  ) async {
    final client = http.Client();
    try {
      final resp = await client.send(http.Request('GET', Uri.parse(url)));
      if (resp.statusCode != 200) {
        throw HttpException('HTTP ${resp.statusCode} for $url');
      }
      final total = resp.contentLength ?? spec.approxBytes;
      // Reserve the last 4% for extraction on archive models.
      final ceiling = spec.files.any((f) => f.isTarBz2) ? 0.95 : 1.0;
      final sink = File(dest).openWrite();
      var received = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(_p(spec, (received / total) * ceiling, 'Downloading…'));
      }
      await sink.close();
    } finally {
      client.close();
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
