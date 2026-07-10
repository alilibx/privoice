import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves where models live, per platform. The app **owns** this directory
/// (app-support), so files it downloads there are always readable — no
/// scoped-storage/FUSE surprises (unlike adb-pushed files during dev).
class PlatformPaths {
  /// Root dir that holds all model subdirectories.
  static Future<Directory> modelsRoot() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'models'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<String> subdir(String name) async {
    final root = await modelsRoot();
    final dir = Directory(p.join(root.path, name));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }
}
