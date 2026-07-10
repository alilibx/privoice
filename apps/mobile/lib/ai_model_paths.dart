import 'package:privoice_models/privoice_models.dart';

import 'settings.dart';

/// Resolves the on-device LLM (GGUF) from the app-owned models dir.
/// Honours the "use larger model" setting, falling back to whatever is present.
class AiModelLocator {
  static final ModelDownloader _dl = ModelDownloader();

  static Future<String?> llama() async {
    final large = await SettingsService.useLargeModel();
    final ordered = large
        ? const [ModelCatalog.llama3b, ModelCatalog.llama1b]
        : const [ModelCatalog.llama1b, ModelCatalog.llama3b];
    for (final spec in ordered) {
      if (await _dl.isInstalled(spec)) {
        return _dl.pathTo(spec, spec.expectedFiles.first);
      }
    }
    return null;
  }
}
