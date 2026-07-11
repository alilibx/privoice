import 'dart:async';

import 'package:fllama/fllama.dart';

import 'action_items.dart';
import 'ai_engine.dart';
import 'map_reduce.dart';
import 'prompts.dart';
import 'title.dart';

/// [AiEngine] backed by fllama (llama.cpp) running a small GGUF model fully
/// on-device. The only file that touches fllama.
///
/// fllama streams tokens via its callback; we surface them through [onToken]
/// and complete on `done`.
class OnDeviceAiEngine implements AiEngine {
  OnDeviceAiEngine(this.modelPath);

  final String modelPath;
  bool _warmed = false;

  Future<String> _run(
    List<ChatMessage> messages, {
    int maxTokens = 512,
    double temperature = 0.4,
    int contextSize = 4096,
    void Function(String partial)? onToken,
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
      if (onToken != null) onToken(response);
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
  Future<void> warmUp() async {
    if (_warmed) return;
    try {
      await _run([ChatMessage.user('hi')], maxTokens: 1);
      _warmed = true;
    } catch (_) {
      // best-effort; the real call will surface any error
    }
  }

  @override
  Future<String> summarize(
    String transcript, {
    String? userInstructions,
    void Function(String partial)? onToken,
    void Function(double progress)? onProgress,
  }) async {
    if (transcript.trim().isEmpty) return '';

    if (!needsMapReduce(transcript)) {
      onProgress?.call(0.1);
      final out = await _run(
        [ChatMessage.user(Prompts.summarizeWhole(transcript, userInstructions))],
        maxTokens: 700,
        onToken: onToken,
      );
      onProgress?.call(1.0);
      return out;
    }

    // Map: summarize each chunk (coarse progress, no token stream).
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

    // Reduce: stream the final minutes.
    final minutes = await _run(
      [ChatMessage.user(Prompts.reduce(partials.join('\n\n'), userInstructions))],
      maxTokens: 800,
      onToken: onToken,
    );
    onProgress?.call(1.0);
    return minutes;
  }

  @override
  Future<List<String>> actionItems(String source) async {
    if (source.trim().isEmpty) return const [];
    // Extract from whatever the caller passed (minutes preferred). Cap to fit
    // the context window; never re-summarize here.
    final out = await _run(
      [ChatMessage.user(Prompts.actionItems(_cap(source, 2500)))],
      maxTokens: 300,
    );
    return parseActionItems(out);
  }

  @override
  Future<String> title(String transcript) async {
    if (transcript.trim().isEmpty) return '';
    final out = await _run(
      [ChatMessage.user(Prompts.title(_cap(transcript, 1500)))],
      maxTokens: 24,
      temperature: 0.3,
    );
    return cleanTitle(out);
  }

  @override
  Future<String> chat(
    List<ChatMessage> messages, {
    String? context,
    void Function(String partial)? onToken,
  }) async {
    final system = context == null || context.trim().isEmpty
        ? Prompts.chatSystem
        : '${Prompts.chatSystem}\n\nMeeting context:\n${_cap(context, 3000)}';
    final full = <ChatMessage>[ChatMessage.system(system), ...messages];
    return _run(full, maxTokens: 512, temperature: 0.6, onToken: onToken);
  }

  /// Word-cap text so it fits the model window.
  static String _cap(String text, int maxWords) {
    final words = text.split(RegExp(r'\s+'));
    if (words.length <= maxWords) return text;
    return '${words.take(maxWords).join(' ')}…';
  }

  @override
  Future<void> dispose() async {}
}
