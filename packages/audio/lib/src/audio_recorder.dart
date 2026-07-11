import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'recording_config.dart';

/// Clean seam over the platform recorder so screens depend on an interface and
/// tests can fake the microphone.
abstract class AudioRecorderHandle {
  Future<bool> hasPermission();

  /// Begin recording to a fresh file in the app's documents dir.
  Future<void> start();

  /// Stop and return the recorded WAV path.
  Future<String> stop();

  Future<void> dispose();

  /// Normalized 0..1 mic level, sampled every [interval].
  Stream<double> levels({Duration interval});
}

/// dBFS (≤ 0) → 0..1. At/below [floorDb] → 0; 0 dBFS → 1.
double normalizeAmplitude(double dbfs, {double floorDb = -50.0}) {
  assert(floorDb < 0);
  return ((dbfs - floorDb) / -floorDb).clamp(0.0, 1.0);
}

/// Records a single meeting to a 16 kHz mono WAV file.
class AppAudioRecorder implements AudioRecorderHandle {
  AppAudioRecorder({RecordingConfig? config})
      : _config = config ?? const RecordingConfig();

  final RecordingConfig _config;
  final AudioRecorder _recorder = AudioRecorder();
  String? _currentPath;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _config.fileName(DateTime.now()));
    _currentPath = path;
    await _recorder.start(_config.toRecordConfig(), path: path);
  }

  @override
  Future<String> stop() async {
    await _recorder.stop();
    final path = _currentPath;
    if (path == null) {
      throw StateError('stop() called before start()');
    }
    return path;
  }

  @override
  Stream<double> levels(
          {Duration interval = const Duration(milliseconds: 150)}) =>
      _recorder
          .onAmplitudeChanged(interval)
          .map((a) => normalizeAmplitude(a.current));

  @override
  Future<void> dispose() => _recorder.dispose();
}
