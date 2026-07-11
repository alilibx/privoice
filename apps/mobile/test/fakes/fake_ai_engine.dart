import 'package:privoice_ai/privoice_ai.dart';

/// Canned [AiEngine] for tests — deterministic, instant, no model.
class FakeAiEngine implements AiEngine {
  FakeAiEngine({
    this.minutes = '### Summary\nFake minutes for tests.',
    this.items = const ['Alice: ship it'],
    this.answer = 'Fake answer.',
    this.titleText = 'Fake Meeting Title',
  });

  final String minutes;
  final List<String> items;
  final String answer;
  final String titleText;

  @override
  Future<void> warmUp() async {}

  @override
  Future<String> summarize(
    String transcript, {
    String? userInstructions,
    void Function(String partial)? onToken,
    void Function(double)? onProgress,
  }) async {
    onToken?.call(minutes);
    onProgress?.call(1.0);
    return minutes;
  }

  @override
  Future<List<String>> actionItems(String source) async => items;

  @override
  Future<String> title(String transcript) async => titleText;

  @override
  Future<String> chat(
    List<ChatMessage> messages, {
    String? context,
    void Function(String partial)? onToken,
  }) async {
    onToken?.call(answer);
    return answer;
  }

  @override
  Future<void> dispose() async {}
}
