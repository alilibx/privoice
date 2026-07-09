/// Role of a chat message.
enum ChatRole { system, user, assistant }

class ChatMessage {
  const ChatMessage(this.role, this.text);
  final ChatRole role;
  final String text;

  factory ChatMessage.system(String t) => ChatMessage(ChatRole.system, t);
  factory ChatMessage.user(String t) => ChatMessage(ChatRole.user, t);
  factory ChatMessage.assistant(String t) => ChatMessage(ChatRole.assistant, t);
}

/// Backend-agnostic AI contract for the meeting smart-actions.
///
/// Implementations: [on-device fllama] now; an online (OpenRouter) engine later.
/// The UI depends only on this interface.
abstract class AiEngine {
  /// Summary / minutes as Markdown. Handles long transcripts via map-reduce.
  /// [onProgress] reports 0..1 coarse progress (useful for long meetings).
  Future<String> summarize(
    String transcript, {
    String? userInstructions,
    void Function(double progress)? onProgress,
  });

  /// Action items / decisions extracted from the transcript, one per entry.
  Future<List<String>> actionItems(String transcript);

  /// Free-form chat grounded in [context] (e.g. the transcript + minutes).
  Future<String> chat(List<ChatMessage> messages, {String? context});

  Future<void> dispose();
}
