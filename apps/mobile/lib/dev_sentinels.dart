import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Directory scanned for the debug-only sentinel files (`.seed`,
/// `.ai_selftest`) that gate dev affordances on a real device.
///
/// Android uses app-external storage so a sentinel can be dropped in with
/// `adb push`. iOS has no such directory — `getExternalStorageDirectory()`
/// throws `UnsupportedError` there — so fall back to app-documents, which is
/// reachable via the simulator's data container.
Future<Directory?> devSentinelDir() async {
  if (Platform.isAndroid) return getExternalStorageDirectory();
  return getApplicationDocumentsDirectory();
}
