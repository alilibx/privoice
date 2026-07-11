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

  @override
  void initState() {
    super.initState();
    _maybeSelfTest();
  }

  /// Headless device proof: if a `.selftest` sentinel exists in external
  /// storage AND the model + sample WAV are present, auto-transcribe on launch
  /// and log the result. Lets us verify the native pipeline via logcat without
  /// mic input. No sentinel → normal app behaviour.
  Future<void> _maybeSelfTest() async {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext == null) return;
      // Flat layout in the app-owned files/ root: adb-pushed files here are
      // readable by the app, whereas adb-created nested subdirs are not (a FUSE
      // scoped-storage quirk that does not occur with the real download flow).
      final base = ext.path;
      final sentinel = File(p.join(base, '.selftest'));
      final encoder = p.join(base, 'encoder.int8.onnx');
      final wav = p.join(base, 'en.wav');
      // ignore: avoid_print
      print('ITEST_DIAG base=$base sentinel=${sentinel.existsSync()} '
          'encoder=${File(encoder).existsSync()} wav=${File(wav).existsSync()}');
      if (!sentinel.existsSync() ||
          !File(encoder).existsSync() ||
          !File(wav).existsSync()) {
        return;
      }
      setState(() {
        _busy = true;
        _status = 'Self-test…';
      });
      final engine = SherpaSttEngine();
      await engine.init(SttModelPaths(
        encoder: encoder,
        decoder: p.join(base, 'decoder.int8.onnx'),
        joiner: p.join(base, 'joiner.int8.onnx'),
        tokens: p.join(base, 'tokens.txt'),
      ));
      final sw = Stopwatch()..start();
      final t = await engine.transcribe(wav);
      sw.stop();
      final rtf = sw.elapsedMilliseconds / t.audioDuration.inMilliseconds;
      // ignore: avoid_print
      print('ITEST_STT rtf=${rtf.toStringAsFixed(2)} '
          'audioMs=${t.audioDuration.inMilliseconds} '
          'transcribeMs=${sw.elapsedMilliseconds} text="${t.fullText}"');
      await engine.dispose();
      setState(() {
        _busy = false;
        _status = 'Self-test done';
        _transcript = t.fullText;
      });
    } catch (e) {
      // ignore: avoid_print
      print('ITEST_STT error=$e');
      setState(() => _busy = false);
    }
  }

  bool _recording = false;
  bool _busy = false;
  bool _initialized = false;
  String _status = 'Idle';
  String _transcript = '';
  String _bench = '';

  /// Spike model location: the app-owned external files/ root (flat).
  /// adb-pushed files here are readable by the app, unlike adb-created nested
  /// subdirs (a scoped-storage/FUSE quirk). The real download flow (S5) will
  /// use a proper nested dir it creates itself.
  Future<String> _modelDir() async {
    final ext = await getExternalStorageDirectory();
    if (ext == null) {
      throw StateError('External storage unavailable (Android only).');
    }
    return ext.path;
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
      await _recorder.start();
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

      // Also emit for `flutter logs` / logcat capture in the benchmark report.
      // ignore: avoid_print
      print('SPIKE_BENCH ${bench.describe()} model=${modelBytes}B');
      // ignore: avoid_print
      print('ITEST_STT text="${t.fullText}"');
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
