import 'package:privoice_ai/privoice_ai.dart';

import 'ai_model_paths.dart';

/// Thin app-side wrapper around the on-device [AiEngine]. Resolves the model
/// lazily and reports when it isn't installed yet (pre-S5 download).
class AiService {
  AiEngine? _engine;

  Future<bool> isAvailable() async => (await AiModelLocator.llama()) != null;

  Future<AiEngine?> _engineOrNull() async {
    if (_engine != null) return _engine;
    final path = await AiModelLocator.llama();
    if (path == null) return null;
    return _engine = OnDeviceAiEngine(path);
  }

  Future<String?> summarize(
    String transcript, {
    void Function(double)? onProgress,
  }) async {
    final e = await _engineOrNull();
    if (e == null) return null;
    return e.summarize(transcript, onProgress: onProgress);
  }

  Future<List<String>?> actionItems(String transcript) async {
    final e = await _engineOrNull();
    if (e == null) return null;
    return e.actionItems(transcript);
  }

  Future<String?> ask(List<ChatMessage> messages, {String? context}) async {
    final e = await _engineOrNull();
    if (e == null) return null;
    return e.chat(messages, context: context);
  }
}
