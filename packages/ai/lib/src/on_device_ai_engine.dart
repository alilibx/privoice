import 'dart:async';

import 'package:fllama/fllama.dart';

import 'ai_engine.dart';
import 'map_reduce.dart';
import 'prompts.dart';

/// [AiEngine] backed by fllama (llama.cpp) running a small GGUF model fully
/// on-device. The only file that touches fllama.
///
/// fllama runs inference off the UI isolate internally and streams tokens via
/// the callback; we complete on `done`.
class OnDeviceAiEngine implements AiEngine {
  OnDeviceAiEngine(this.modelPath);

  final String modelPath;

  Future<String> _run(
    List<ChatMessage> messages, {
    int maxTokens = 512,
    double temperature = 0.4,
    int contextSize = 4096,
  }) {
    final req = OpenAiRequest(
      modelPath: modelPath,
      messages: messages.map((m) => Message(_role(m.role), m.text)).toList(),
      maxTokens: maxTokens,
      temperature: temperature,
      topP: 0.9,
      numGpuLayers: 99, // safe no-op where there's no GPU (Android/web)
      contextSize: contextSize,
    );

    final completer = Completer<String>();
    fllamaChat(req, (response, _, done) {
      if (done && !completer.isCompleted) {
        completer.complete(response.trim());
      }
    });
    return completer.future;
  }

  static Role _role(ChatRole r) => switch (r) {
        ChatRole.system => Role.system,
        ChatRole.user => Role.user,
        ChatRole.assistant => Role.assistant,
      };

  @override
  Future<String> summarize(
    String transcript, {
    String? userInstructions,
    void Function(double progress)? onProgress,
  }) async {
    if (transcript.trim().isEmpty) return '';

    if (!needsMapReduce(transcript)) {
      onProgress?.call(0.1);
      final out = await _run(
        [ChatMessage.user(Prompts.summarizeWhole(transcript, userInstructions))],
        maxTokens: 700,
      );
      onProgress?.call(1.0);
      return out;
    }

    // Map: summarize each chunk.
    final chunks = chunkTranscript(transcript);
    final partials = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      final s = await _run(
        [ChatMessage.user(Prompts.mapChunk(chunks[i], i, chunks.length))],
        maxTokens: 400,
      );
      partials.add(s);
      onProgress?.call((i + 1) / (chunks.length + 1));
    }

    // Reduce: summarize the summaries into final minutes.
    final minutes = await _run(
      [ChatMessage.user(Prompts.reduce(partials.join('\n\n'), userInstructions))],
      maxTokens: 800,
    );
    onProgress?.call(1.0);
    return minutes;
  }

  @override
  Future<List<String>> actionItems(String transcript) async {
    if (transcript.trim().isEmpty) return const [];
    // For long meetings, extract from the condensed minutes for coherence.
    final source =
        needsMapReduce(transcript) ? await summarize(transcript) : transcript;
    final out = await _run(
      [ChatMessage.user(Prompts.actionItems(source))],
      maxTokens: 300,
    );
    return out
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'^\s*[-*]\s*'), '').trim())
        .where((l) => l.isNotEmpty && l.toLowerCase() != 'none')
        .toList();
  }

  @override
  Future<String> chat(List<ChatMessage> messages, {String? context}) async {
    final system = context == null || context.trim().isEmpty
        ? Prompts.chatSystem
        : '${Prompts.chatSystem}\n\nMeeting context:\n${_cap(context, 3000)}';
    final full = <ChatMessage>[ChatMessage.system(system), ...messages];
    return _run(full, maxTokens: 512, temperature: 0.6);
  }

  /// Word-cap the grounding context so it fits the model window.
  static String _cap(String text, int maxWords) {
    final words = text.split(RegExp(r'\s+'));
    if (words.length <= maxWords) return text;
    return '${words.take(maxWords).join(' ')}…';
  }

  @override
  Future<void> dispose() async {}
}
