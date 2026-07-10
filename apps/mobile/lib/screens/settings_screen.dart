import 'package:flutter/material.dart';
import 'package:privoice_models/privoice_models.dart';

import '../settings.dart';
import 'model_download_screen.dart';

/// Settings: appearance (theme), model management, privacy.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.themeMode});

  final ValueNotifier<ThemeMode> themeMode;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _dl = ModelDownloader();
  bool _loading = true;
  bool _useLarge = false;
  bool _largeInstalled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final useLarge = await SettingsService.useLargeModel();
    final installed = await _dl.isInstalled(ModelCatalog.llama3b);
    if (!mounted) return;
    setState(() {
      _useLarge = useLarge;
      _largeInstalled = installed;
      _loading = false;
    });
  }

  Future<void> _toggleLarge(bool value) async {
    if (value && !_largeInstalled) {
      final ok = await _confirmDownload();
      if (ok != true) return;
      if (!mounted) return;
      final done = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Higher-quality model')),
          body: ModelDownloadScreen(
            specs: const [ModelCatalog.llama3b],
            showScaffold: false,
            onDone: () => Navigator.of(context).pop(true),
          ),
        ),
      ));
      if (done != true) return;
    }
    await SettingsService.setUseLargeModel(value);
    await _load();
  }

  Future<bool?> _confirmDownload() {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Download larger model?'),
        content: const Text(
          'The higher-quality AI model (Llama 3.2 3B, ~2 GB) gives better '
          'minutes but is slower and uses more battery and heat, especially on '
          'older phones. Download it now?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Download')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _sectionHeader('Appearance', scheme),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: ValueListenableBuilder<ThemeMode>(
                    valueListenable: widget.themeMode,
                    builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                            value: ThemeMode.system,
                            label: Text('System'),
                            icon: Icon(Icons.brightness_auto_outlined)),
                        ButtonSegment(
                            value: ThemeMode.light,
                            label: Text('Light'),
                            icon: Icon(Icons.light_mode_outlined)),
                        ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('Dark'),
                            icon: Icon(Icons.dark_mode_outlined)),
                      ],
                      selected: {mode},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) async {
                        widget.themeMode.value = s.first;
                        await SettingsService.setThemeMode(s.first);
                      },
                    ),
                  ),
                ),
                const Divider(),
                _sectionHeader('AI model', scheme),
                SwitchListTile(
                  value: _useLarge,
                  onChanged: _toggleLarge,
                  title: const Text('Higher-quality AI model'),
                  subtitle: Text(
                    _useLarge
                        ? 'Using Llama 3.2 3B — slower, more accurate'
                        : 'Using Llama 3.2 1B — fast, efficient (default)',
                  ),
                  secondary: const Icon(Icons.auto_awesome),
                ),
                const Divider(),
                _sectionHeader('Privacy', scheme),
                ListTile(
                  leading: Icon(Icons.lock_outline, color: scheme.primary),
                  title: const Text('Everything runs on your device'),
                  subtitle: const Text(
                      'Recordings, transcripts, and AI all stay on your phone. '
                      'Nothing is uploaded.'),
                ),
              ],
            ),
    );
  }

  Widget _sectionHeader(String text, ColorScheme scheme) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(text,
            style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.5)),
      );
}
