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
/// Implementations: on-device fllama now; an online (OpenRouter) engine later.
/// The UI depends only on this interface.
abstract class AiEngine {
  /// Loads the model into memory so the first real call isn't cold. Cheap to
  /// call repeatedly (no-op once warm).
  Future<void> warmUp();

  /// Summary / minutes as Markdown. Handles long transcripts via map-reduce.
  /// [onToken] streams the cumulative text as it generates; [onProgress]
  /// reports 0..1 coarse progress (useful for long meetings).
  Future<String> summarize(
    String transcript, {
    String? userInstructions,
    void Function(String partial)? onToken,
    void Function(double progress)? onProgress,
  });

  /// Action items / decisions extracted from [source] — pass the generated
  /// minutes when available (short + coherent), else the transcript. One call;
  /// never re-summarizes internally.
  Future<List<String>> actionItems(String source);

  /// Free-form chat grounded in [context] (e.g. the transcript + minutes).
  /// [onToken] streams the cumulative reply.
  Future<String> chat(
    List<ChatMessage> messages, {
    String? context,
    void Function(String partial)? onToken,
  });

  Future<void> dispose();
}
