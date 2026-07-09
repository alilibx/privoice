/// Splits a long transcript into word-bounded chunks so each fits comfortably
/// in a small on-device LLM's context window.
///
/// The single most important lever for minutes quality on long meetings: chunk
/// (map), summarize each, then summarize the summaries (reduce).
List<String> chunkTranscript(String transcript, {int wordsPerChunk = 700}) {
  final words = transcript.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.length <= wordsPerChunk) {
    return words.isEmpty ? const [] : [words.join(' ')];
  }
  final chunks = <String>[];
  for (var i = 0; i < words.length; i += wordsPerChunk) {
    final end = (i + wordsPerChunk < words.length) ? i + wordsPerChunk : words.length;
    chunks.add(words.sublist(i, end).join(' '));
  }
  return chunks;
}

/// True when the transcript is long enough to need map-reduce.
bool needsMapReduce(String transcript, {int wordsPerChunk = 700}) {
  final count = transcript.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  return count > wordsPerChunk;
}
