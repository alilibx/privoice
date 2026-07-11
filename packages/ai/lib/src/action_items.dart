// Parsing for the model's raw action-item output.
//
// Small on-device models are messy: they use assorted bullet glyphs, number
// their lines, and — prompted for owners — emit placeholder "None" lines after
// each item. This turns that raw text into a clean list, dropping bullets,
// numbering, and any "none"/"no action items" placeholder line.

// Leading list markers: -, *, •, ·, –, —, or ordered "1." / "1)".
final _leadingMarker = RegExp(r'^\s*(?:[-*•·–—]+|\d+[.)])\s*');

/// True when [line] is a placeholder the model emits for "nothing here"
/// (e.g. "None", "None.", "(none)", "N/A", "No action items identified").
bool _isPlaceholder(String line) {
  final s = line.toLowerCase().trim();
  final lettersOnly = s.replaceAll(RegExp(r'[^a-z]'), '');
  if (lettersOnly == 'none' || lettersOnly == 'na') return true;
  // Short "none …" placeholders ("none identified", "none found") but not a
  // real item that happens to open with the word "none".
  if (s.startsWith('none') && s.length <= 24) return true;
  return s.startsWith('no action') || s.startsWith('there are no');
}

/// Parse [raw] model output into clean action-item strings.
List<String> parseActionItems(String raw) {
  return raw
      .split('\n')
      .map((l) => l.replaceFirst(_leadingMarker, '').trim())
      .where((l) => l.isNotEmpty && !_isPlaceholder(l))
      .toList();
}
