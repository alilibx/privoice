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
/// widget-tested without `file_picker`. Every other outside-world dependency is
/// injectable for the same reason: the defaults reach a native decoder, a
/// `compute` isolate, the model downloader and `path_provider`, none of which
/// work inside `testWidgets`.
class ImportScreen extends StatefulWidget {
  const ImportScreen({
    super.key,
    required this.repository,
    required this.sourcePath,
    this.importer,
    this.transcriber,
    this.locateModel,
    this.workDir,
  });

  final MeetingRepository repository;
  final String sourcePath;
  final AudioImporter? importer;

  /// Defaults to [transcribeFileInBackground].
  final FileTranscriber? transcriber;

  /// Defaults to [ModelLocator.parakeet].
  final SttModelResolver? locateModel;

  /// Where the converted WAV is written. Defaults to app documents.
  final Future<Directory> Function()? workDir;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  late final AudioImporter _importer =
      widget.importer ?? const AudioDecoderImporter();
  late final FileTranscriber _transcribe =
      widget.transcriber ?? transcribeFileInBackground;
  late final SttModelResolver _locateModel =
      widget.locateModel ?? ModelLocator.parakeet;
  late final Future<Directory> Function() _workDir =
      widget.workDir ?? getApplicationDocumentsDirectory;

  _Phase _phase = _Phase.converting;
  double _progress = 0;
  String _error = '';
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_running) return; // 'Try again' is only shown in the error phase, but
    if (!mounted) return; // a double-tap must not start two imports.
    setState(() {
      _running = true;
      _phase = _Phase.converting;
      _progress = 0;
      _error = '';
    });

    String? wavPath;
    try {
      // Resolve the model BEFORE transcoding: converting first would spend
      // minutes and ~115 MB per hour of audio only to fail on a model that was
      // never there. HomeScreen also gates Import on sttReady; this is the
      // backstop for a model that disappears between the two checks.
      final model = await _locateModel();
      if (model == null) {
        throw const AudioImportException(
          'The speech model is not ready yet. Try again once setup finishes.',
        );
      }

      final dir = await _workDir();
      wavPath = p.join(
        dir.path,
        'imported_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      await _importer.toSttWav(
        sourcePath: widget.sourcePath,
        targetPath: wavPath,
      );

      // Deliberately not `if (!mounted) return`: an early return here would
      // skip the catch's cleanup and orphan the converted WAV in app documents
      // forever. Finishing the work instead keeps the file referenced by a real
      // Meeting row, which is the honest outcome — the import did succeed.
      if (mounted) setState(() => _phase = _Phase.transcribing);

      final reader = await WavReader.open(wavPath);
      final duration = reader.duration;
      await reader.close();

      final transcript = await _transcribe(
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
    } finally {
      _running = false;
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
    // Block leaving mid-import, exactly as RecordScreen does mid-transcribe.
    // Nothing cancels the transcode or the isolate, so backing out used to let a
    // successful import land silently: the Meeting was inserted but the pop(true)
    // that refreshes Home never fired, and the meeting only appeared on restart.
    final canLeave = _phase == _Phase.error;
    return PopScope(
      canPop: canLeave,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Import recording'),
        // Disable rather than leave enabled-but-inert. PopScope already refuses
        // the pop, so a tappable back arrow that silently does nothing reads as
        // a broken app; RecordScreen disables its close icon the same way.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: canLeave ? () => Navigator.of(context).maybePop() : null,
        ),
      ),
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
      ),
    );
  }
}
