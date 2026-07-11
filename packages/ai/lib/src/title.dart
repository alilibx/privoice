/// Clean the model's raw title output into a short, single-line title:
/// first line only, no surrounding quotes, no "Title:" label, no trailing
/// punctuation, capped to [maxWords] words.
String cleanTitle(String raw, {int maxWords = 8}) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  s = s.split('\n').first.trim();
  s = s.replaceFirst(RegExp(r'^title\s*[:\-]\s*', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'''^["'“”‘’]+|["'“”‘’]+$'''), '').trim();
  s = s.replaceFirst(RegExp(r'[.!?,;:\s]+$'), '').trim();
  final words = s.split(RegExp(r'\s+'));
  if (words.length > maxWords) s = words.take(maxWords).join(' ');
  return s;
}
