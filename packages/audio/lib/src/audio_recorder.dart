import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'recording_config.dart';

/// Records a single meeting to a 16 kHz mono WAV file.
///
/// Lifecycle: [hasPermission] → [start] → [stop] (returns the WAV path).
class AppAudioRecorder {
  AppAudioRecorder({RecordingConfig? config})
      : _config = config ?? const RecordingConfig();

  final RecordingConfig _config;
  final AudioRecorder _recorder = AudioRecorder();
  String? _currentPath;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start(String dirPath) async {
    final path = p.join(dirPath, _config.fileName(DateTime.now()));
    _currentPath = path;
    await _recorder.start(_config.toRecordConfig(), path: path);
  }

  Future<String> stop() async {
    await _recorder.stop();
    final path = _currentPath;
    if (path == null) {
      throw StateError('stop() called before start()');
    }
    return path;
  }

  Future<void> dispose() => _recorder.dispose();
}
