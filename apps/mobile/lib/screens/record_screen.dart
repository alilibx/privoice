import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:privoice_audio/privoice_audio.dart';
import 'package:privoice_core/privoice_core.dart';
import 'package:privoice_stt/privoice_stt.dart';

import '../model_paths.dart';

enum _Phase { idle, recording, transcribing, error }

/// Record → (background) transcribe → persist a [Meeting]. Pops `true` when a
/// meeting was saved so the caller can refresh.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, required this.repository});

  final MeetingRepository repository;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final AppAudioRecorder _recorder = AppAudioRecorder();
  final Stopwatch _watch = Stopwatch();
  Timer? _ticker;

  _Phase _phase = _Phase.idle;
  Duration _elapsed = Duration.zero;
  String _error = '';

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      setState(() {
        _phase = _Phase.error;
        _error = 'Microphone permission is needed to record.';
      });
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    await _recorder.start(dir.path);
    _watch
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      setState(() => _elapsed = _watch.elapsed);
    });
    setState(() => _phase = _Phase.recording);
  }

  Future<void> _stopAndTranscribe() async {
    _ticker?.cancel();
    _watch.stop();
    final durationMs = _watch.elapsedMilliseconds;
    final wavPath = await _recorder.stop();
    setState(() => _phase = _Phase.transcribing);

    try {
      final model = await ModelLocator.parakeet();
      if (model == null) {
        setState(() {
          _phase = _Phase.error;
          _error =
              'Speech model not found on device.\nPush it to the app files dir, '
              'or wait for the in-app download (coming soon).';
        });
        return;
      }

      final transcript = await transcribeFileInBackground(model, wavPath);

      final meeting = Meeting(
        title: _defaultTitle(),
        createdAt: DateTime.now(),
        audioPath: wavPath,
        durationMs: durationMs,
        transcript: transcript.fullText,
        status: MeetingStatus.done,
      );
      await widget.repository.insert(meeting);

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _phase = _Phase.error;
        _error = 'Transcription failed: $e';
      });
    }
  }

  String _defaultTitle() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    return 'Meeting ${now.day}/${now.month} $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New recording'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _phase == _Phase.transcribing
              ? null
              : () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: _body(scheme)),
      ),
    );
  }

  Widget _body(ColorScheme scheme) {
    switch (_phase) {
      case _Phase.transcribing:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
                width: 44, height: 44, child: CircularProgressIndicator()),
            const SizedBox(height: 24),
            Text('Transcribing…',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Running on-device. Longer meetings take a little while — '
              'nothing leaves your phone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        );
      case _Phase.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 16),
            Text(_error, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Back'),
            ),
          ],
        );
      case _Phase.idle:
      case _Phase.recording:
        final recording = _phase == _Phase.recording;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _fmt(_elapsed),
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w300,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: recording ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 48),
            _RecordButton(
              recording: recording,
              onTap: recording ? _stopAndTranscribe : _start,
            ),
            const SizedBox(height: 32),
            Text(
              recording ? 'Tap to stop & transcribe' : 'Tap to start recording',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        );
    }
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.recording, required this.onTap});

  final bool recording;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 108,
        height: 108,
        decoration: BoxDecoration(
          color: recording ? scheme.errorContainer : scheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          recording ? Icons.stop_rounded : Icons.mic_rounded,
          size: 48,
          color: recording ? scheme.onErrorContainer : scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
