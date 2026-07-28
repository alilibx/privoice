import 'package:privoice_models/privoice_models.dart';
import 'package:privoice_stt/privoice_stt.dart';

/// The signature of [ModelLocator.parakeet].
///
/// Exists so a caller can hold model resolution as a dependency rather than
/// reaching for the static: the real one hits the S5 downloader and the app-owned
/// filesystem, neither of which exists in a widget test.
typedef SttModelResolver = Future<SttModelPaths?> Function();

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
