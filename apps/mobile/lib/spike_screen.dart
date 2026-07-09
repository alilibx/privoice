import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:privoice_audio/privoice_audio.dart';
import 'package:privoice_stt/privoice_stt.dart';

import 'benchmark.dart';

/// S1 spike: record → transcribe → measure. Not the product UI — a
/// throwaway harness to get real RTF / RAM / model-size numbers on a device.
class SpikeScreen extends StatefulWidget {
  const SpikeScreen({super.key});

  @override
  State<SpikeScreen> createState() => _SpikeScreenState();
}

class _SpikeScreenState extends State<SpikeScreen> {
  final AppAudioRecorder _recorder = AppAudioRecorder();
  final SherpaSttEngine _stt = SherpaSttEngine();

  bool _recording = false;
  bool _busy = false;
  bool _initialized = false;
  String _status = 'Idle';
  String _transcript = '';
  String _bench = '';

  /// Matches tools/fetch-and-push-model.sh DEST:
  /// `/sdcard/Android/data/<app>/files/models/parakeet-tdt-v3-int8`
  Future<String> _modelDir() async {
    final ext = await getExternalStorageDirectory();
    if (ext == null) {
      throw StateError('External storage unavailable (Android only).');
    }
    return p.join(ext.path, 'models', 'parakeet-tdt-v3-int8');
  }

  Future<void> _ensureInit() async {
    if (_initialized) return;
    final m = await _modelDir();
    await _stt.init(SttModelPaths(
      encoder: p.join(m, 'encoder.int8.onnx'),
      decoder: p.join(m, 'decoder.int8.onnx'),
      joiner: p.join(m, 'joiner.int8.onnx'),
      tokens: p.join(m, 'tokens.txt'),
    ));
    _initialized = true;
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      final path = await _recorder.stop();
      setState(() {
        _recording = false;
        _busy = true;
        _status = 'Transcribing…';
      });
      await _transcribe(path);
    } else {
      if (!await _recorder.hasPermission()) {
        setState(() => _status = 'Microphone permission denied');
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      await _recorder.start(dir.path);
      setState(() {
        _recording = true;
        _status = 'Recording…';
      });
    }
  }

  Future<void> _transcribe(String wavPath) async {
    try {
      await _ensureInit();
      final sw = Stopwatch()..start();
      final t = await _stt.transcribe(wavPath);
      sw.stop();

      final bench = BenchmarkResult.compute(
        audioMs: t.audioDuration.inMilliseconds,
        transcribeMs: sw.elapsedMilliseconds,
      );
      final modelBytes = await _dirSize(await _modelDir());

      setState(() {
        _transcript = t.fullText;
        _bench = '${bench.describe()} | '
            'model=${(modelBytes / 1e6).toStringAsFixed(0)}MB';
        _status = 'Done';
        _busy = false;
      });

      // Also emit for `flutter logs` capture in the benchmark report.
      // ignore: avoid_print
      print('SPIKE_BENCH ${bench.describe()} model=${modelBytes}B');
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _busy = false;
      });
    }
  }

  Future<int> _dirSize(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  @override
  void dispose() {
    _recorder.dispose();
    _stt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privoice STT Spike')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: $_status'),
            const SizedBox(height: 8),
            if (_bench.isNotEmpty)
              Text(_bench,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Text(_transcript.isEmpty ? '(no transcript yet)' : _transcript),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _toggleRecord,
                child: Text(_recording ? 'Stop & Transcribe' : 'Record'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
