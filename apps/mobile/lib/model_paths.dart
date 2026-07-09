import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:privoice_stt/privoice_stt.dart';

/// Resolves the on-device STT model location for the spike/S2 build.
///
/// Currently the flat external files/ root (populated via adb push during dev).
/// S5 replaces this with a proper first-launch download into an owned dir.
class ModelLocator {
  static Future<SttModelPaths?> parakeet() async {
    final ext = await getExternalStorageDirectory();
    if (ext == null) return null;
    final base = ext.path;
    final paths = SttModelPaths(
      encoder: p.join(base, 'encoder.int8.onnx'),
      decoder: p.join(base, 'decoder.int8.onnx'),
      joiner: p.join(base, 'joiner.int8.onnx'),
      tokens: p.join(base, 'tokens.txt'),
    );
    if (!File(paths.encoder).existsSync() || !File(paths.tokens).existsSync()) {
      return null;
    }
    return paths;
  }
}
