import 'package:flutter/material.dart';
import 'package:privoice_models/privoice_models.dart';

import 'model_download_screen.dart';

/// Shows the first-launch download flow until the default model set is present,
/// then reveals the app.
class ModelGate extends StatefulWidget {
  const ModelGate({super.key, required this.child});

  final Widget child;

  @override
  State<ModelGate> createState() => _ModelGateState();
}

class _ModelGateState extends State<ModelGate> {
  final _dl = ModelDownloader();
  late Future<bool> _ready;

  @override
  void initState() {
    super.initState();
    _ready = _check();
  }

  Future<bool> _check() async {
    for (final spec in ModelCatalog.defaultSet) {
      if (!await _dl.isInstalled(spec)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _ready,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snap.data == true) return widget.child;
        return ModelDownloadScreen(
          specs: ModelCatalog.defaultSet,
          onDone: () => setState(() => _ready = Future.value(true)),
        );
      },
    );
  }
}
