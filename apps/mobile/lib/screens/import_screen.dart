import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:privoice_audio/privoice_audio.dart';
import 'package:privoice_core/privoice_core.dart';
import 'package:privoice_stt/privoice_stt.dart';

import '../model_paths.dart';

enum _Phase { converting, transcribing, error }

/// Import an existing recording: transcode → chunked transcribe → persist a
/// [Meeting]. Pops `true` when a meeting was saved.
///
/// Takes a [sourcePath] rather than doing its own file picking, so it can be
/// widget-tested without `file_picker`.
class ImportScreen extends StatefulWidget {
  const ImportScreen({
    super.key,
    required this.repository,
    required this.sourcePath,
    this.importer,
  });

  final MeetingRepository repository;
  final String sourcePath;
  final AudioImporter? importer;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  late final AudioImporter _importer =
      widget.importer ?? const AudioDecoderImporter();

  _Phase _phase = _Phase.converting;
  double _progress = 0;
  String _error = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    setState(() {
      _phase = _Phase.converting;
      _progress = 0;
      _error = '';
    });

    String? wavPath;
    try {
      final dir = await getApplicationDocumentsDirectory();
      wavPath = p.join(
        dir.path,
        'imported_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      await _importer.toSttWav(
        sourcePath: widget.sourcePath,
        targetPath: wavPath,
      );

      final model = await ModelLocator.parakeet();
      if (model == null) {
        throw const AudioImportException(
          'The speech model is not ready yet. Try again once setup finishes.',
        );
      }

      if (!mounted) return;
      setState(() => _phase = _Phase.transcribing);

      final reader = await WavReader.open(wavPath);
      final duration = reader.duration;
      await reader.close();

      final transcript = await transcribeFileInBackground(
        model,
        wavPath,
        onProgress: (f) {
          if (mounted) setState(() => _progress = f);
        },
      );

      await widget.repository.insert(Meeting(
        title: _defaultTitle(),
        createdAt: DateTime.now(),
        audioPath: wavPath,
        durationMs: duration.inMilliseconds,
        transcript: transcript.fullText,
        status: MeetingStatus.done,
      ));

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // Leave nothing half-written behind: a partial WAV would otherwise sit
      // in app storage forever, and no Meeting row is inserted on failure.
      if (wavPath != null) {
        final f = File(wavPath);
        if (await f.exists()) await f.delete();
      }
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = e is AudioImportException
            ? e.message
            : "That file couldn't be imported.";
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
      appBar: AppBar(title: const Text('Import recording')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: switch (_phase) {
            _Phase.converting => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                      width: 120, child: LinearProgressIndicator(minHeight: 4)),
                  SizedBox(height: 16),
                  Text('Converting audio…'),
                ],
              ),
            _Phase.transcribing => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(
                        minHeight: 4, value: _progress == 0 ? null : _progress),
                  ),
                  const SizedBox(height: 16),
                  Text('Transcribing… ${(_progress * 100).round()}%'),
                ],
              ),
            _Phase.error => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: scheme.error),
                  const SizedBox(height: 16),
                  Text("Couldn't import that file",
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(_error,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _run,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Try again'),
                  ),
                ],
              ),
          },
        ),
      ),
    );
  }
}
