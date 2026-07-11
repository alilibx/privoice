import 'dart:async';

import 'package:flutter/material.dart';
import 'package:privoice_audio/privoice_audio.dart';
import 'package:privoice_core/privoice_core.dart';
import 'package:privoice_stt/privoice_stt.dart';

import '../model_paths.dart';
import '../rolling_levels.dart';

enum _Phase { idle, recording, transcribing, error }

const _waveCapacity = 44;

/// Record → (background) transcribe → persist a [Meeting]. Pops `true` when a
/// meeting was saved so the caller can refresh.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, required this.repository, this.recorder});

  final MeetingRepository repository;
  final AudioRecorderHandle? recorder;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  late final AudioRecorderHandle _recorder =
      widget.recorder ?? AppAudioRecorder();
  final Stopwatch _watch = Stopwatch();
  final RollingLevels _levels = RollingLevels(_waveCapacity);
  Timer? _ticker;
  StreamSubscription<double>? _levelSub;

  _Phase _phase = _Phase.idle;
  Duration _elapsed = Duration.zero;
  String _error = '';

  @override
  void dispose() {
    _ticker?.cancel();
    _levelSub?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _start() async {
    if (_phase != _Phase.idle && _phase != _Phase.error) return;
    if (!await _recorder.hasPermission()) {
      setState(() {
        _phase = _Phase.error;
        _error = 'Microphone permission is needed to record.';
      });
      return;
    }
    await _recorder.start();
    _watch
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() => _elapsed = _watch.elapsed);
    });
    _levelSub = _recorder.levels().listen((l) {
      if (mounted) setState(() => _levels.push(l));
    });
    setState(() => _phase = _Phase.recording);
  }

  Future<void> _stopAndTranscribe() async {
    _ticker?.cancel();
    await _levelSub?.cancel();
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
    final recording = _phase == _Phase.recording;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: recording
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: scheme.error, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text('REC',
                      style: TextStyle(
                          color: scheme.error,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          letterSpacing: 0.5)),
                ],
              )
            : const Text('New recording'),
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
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                  color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(Icons.auto_awesome,
                  size: 34, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 22),
            Text('Transcribing…',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            SizedBox(
              width: 180,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: const LinearProgressIndicator(minHeight: 5),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Running on your phone — nothing is uploaded.',
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
                fontSize: 48,
                fontWeight: FontWeight.w300,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: recording ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 36),
            _Waveform(
              key: const Key('waveform'),
              samples: _levels.samples,
              capacity: _waveCapacity,
              active: recording,
            ),
            const SizedBox(height: 40),
            _RecordButton(
              key: const Key('recordButton'),
              recording: recording,
              onTap: recording ? _stopAndTranscribe : _start,
            ),
            const SizedBox(height: 24),
            Text(
              recording ? 'Tap to stop & transcribe' : 'Tap to start recording',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        );
    }
  }
}

/// Right-aligned scrolling bars: newest sample at the right, older bars fade.
class _Waveform extends StatelessWidget {
  const _Waveform({
    super.key,
    required this.samples,
    required this.capacity,
    required this.active,
  });

  final List<double> samples;
  final int capacity;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recent = samples.length > capacity
        ? samples.sublist(samples.length - capacity)
        : samples;
    final values = <double>[
      ...List<double>.filled(capacity - recent.length, 0.0),
      ...recent,
    ];
    const maxH = 84.0;
    return SizedBox(
      height: maxH,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < values.length; i++)
            Container(
              width: 3,
              height: 3 + values[i] * (maxH - 3),
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: scheme.primary
                    .withValues(alpha: active ? 0.25 + 0.75 * (i / capacity) : 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({super.key, required this.recording, required this.onTap});

  final bool recording;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: 92,
        height: 92,
        decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
        child: recording
            ? Center(
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: scheme.onPrimary,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              )
            : Icon(Icons.mic_rounded, size: 42, color: scheme.onPrimary),
      ),
    );
  }
}
