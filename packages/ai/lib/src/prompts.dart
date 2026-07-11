/// Prompt templates for the meeting smart-actions. Kept in one place so tone
/// and structure are consistent and easy to tune.
class Prompts {
  /// Map step: summarize one chunk of a longer meeting.
  static String mapChunk(String chunk, int index, int total) {
    return 'This is part ${index + 1} of $total of a meeting transcript. '
        'Summarize the key points, decisions, and any tasks mentioned in this '
        'part as concise bullet points. Do not add information that is not '
        'present.\n\nTranscript part:\n$chunk';
  }

  /// Reduce step: combine per-chunk summaries into final minutes.
  static String reduce(String combinedSummaries, String? userInstructions) {
    final extra = (userInstructions != null && userInstructions.trim().isNotEmpty)
        ? '\n\nThe user specifically wants: ${userInstructions.trim()}'
        : '';
    return 'Below are notes from consecutive parts of one meeting. Write clean, '
        'well-structured minutes in Markdown with these sections: '
        '**Summary**, **Key points**, **Decisions**, **Action items**. '
        'Be concise and faithful to the notes; omit empty sections.$extra'
        '\n\nNotes:\n$combinedSummaries';
  }

  /// Single-shot summary for short meetings.
  static String summarizeWhole(String transcript, String? userInstructions) {
    final extra = (userInstructions != null && userInstructions.trim().isNotEmpty)
        ? '\n\nThe user specifically wants: ${userInstructions.trim()}'
        : '';
    return 'Write clean, well-structured meeting minutes in Markdown from the '
        'transcript below, with sections: **Summary**, **Key points**, '
        '**Decisions**, **Action items**. Be concise and faithful; omit empty '
        'sections.$extra\n\nTranscript:\n$transcript';
  }

  static String actionItems(String transcript) {
    return 'Extract the action items from this meeting transcript. Return ONLY '
        'a plain list with one action item per line, each line starting with '
        '"- ". If an owner is mentioned, include it inline in the same line. '
        'Do not add owner, status, or placeholder lines. If there are no '
        'action items at all, reply with exactly: None'
        '\n\nTranscript:\n$transcript';
  }

  static const String chatSystem =
      'You are a helpful assistant inside a private, on-device meeting app. '
      'When meeting context is provided, ground your answers in it and be '
      'concise. If asked to draft something (email, message), produce it '
      'directly.';
}
