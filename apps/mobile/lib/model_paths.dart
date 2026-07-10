import 'package:privoice_models/privoice_models.dart';
import 'package:privoice_stt/privoice_stt.dart';

/// Resolves the on-device STT model from the app-owned models dir (populated by
/// the S5 downloader). Returns null until it's installed.
class ModelLocator {
  static final ModelDownloader _dl = ModelDownloader();

  static Future<SttModelPaths?> parakeet() async {
    const spec = ModelCatalog.parakeetStt;
    if (!await _dl.isInstalled(spec)) return null;
    return SttModelPaths(
      encoder: await _dl.pathTo(spec, 'encoder.int8.onnx'),
      decoder: await _dl.pathTo(spec, 'decoder.int8.onnx'),
      joiner: await _dl.pathTo(spec, 'joiner.int8.onnx'),
      tokens: await _dl.pathTo(spec, 'tokens.txt'),
    );
  }
}
