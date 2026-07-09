import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves the on-device LLM (GGUF) location for the spike/S3 build.
/// Flat external files/ root for now; S5 replaces with an in-app download.
class AiModelLocator {
  static const fileName = 'llama-3.2-1b-instruct-q4.gguf';

  static Future<String?> llama() async {
    final ext = await getExternalStorageDirectory();
    if (ext == null) return null;
    final path = p.join(ext.path, fileName);
    return File(path).existsSync() ? path : null;
  }
}
