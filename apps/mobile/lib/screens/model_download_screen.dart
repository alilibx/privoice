import 'package:flutter/material.dart';
import 'package:privoice_models/privoice_models.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Downloads a set of models with progress. Used for first-launch setup and
/// for fetching the larger model from Settings.
class ModelDownloadScreen extends StatefulWidget {
  const ModelDownloadScreen({
    super.key,
    required this.specs,
    required this.onDone,
    this.title = 'Set up Privoice',
    this.showScaffold = true,
  });

  final List<ModelSpec> specs;
  final VoidCallback onDone;
  final String title;
  final bool showScaffold;

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

enum _S { intro, downloading, error, done }

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  final _dl = ModelDownloader();
  _S _state = _S.intro;
  String _label = '';
  String _phase = '';
  double _fraction = 0;
  int _index = 0;
  String _error = '';

  int get _totalBytes =>
      widget.specs.fold(0, (s, m) => s + m.approxBytes);
  String get _totalLabel =>
      '${(_totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() => _state = _S.downloading);
    WakelockPlus.enable(); // keep the screen on during the one-time download
    try {
      for (var i = 0; i < widget.specs.length; i++) {
        setState(() => _index = i);
        await _dl.install(widget.specs[i], (p) {
          if (!mounted) return;
          setState(() {
            _label = p.label;
            _phase = p.phase;
            _fraction = p.fraction;
          });
        });
      }
      setState(() => _state = _S.done);
      widget.onDone();
    } catch (e) {
      setState(() {
        _state = _S.error;
        _error = '$e';
      });
    } finally {
      WakelockPlus.disable();
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: _body(Theme.of(context).colorScheme),
      ),
    );
    if (!widget.showScaffold) return body;
    return Scaffold(appBar: AppBar(title: Text(widget.title)), body: body);
  }

  Widget _body(ColorScheme scheme) {
    switch (_state) {
      case _S.intro:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_for_offline_outlined,
                size: 64, color: scheme.primary),
            const SizedBox(height: 20),
            Text('Download on-device models',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
              'Privoice runs speech-to-text and AI entirely on your phone. '
              'It needs a one-time download of about $_totalLabel. '
              'Best on Wi-Fi — nothing is uploaded, ever.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _run,
              icon: const Icon(Icons.download_rounded),
              label: Text('Download ($_totalLabel)'),
            ),
          ],
        );
      case _S.downloading:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${_index + 1} of ${widget.specs.length}',
                style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(_label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: _fraction, minHeight: 8),
            ),
            const SizedBox(height: 10),
            Text('$_phase ${(_fraction * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        );
      case _S.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 56, color: scheme.error),
            const SizedBox(height: 16),
            Text('Download failed', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            FilledButton(onPressed: _run, child: const Text('Retry')),
          ],
        );
      case _S.done:
        return const SizedBox.shrink();
    }
  }
}
