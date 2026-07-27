import 'dart:typed_data';

/// Builds WAV bytes for tests. Defaults are the format our pipeline produces
/// (16 kHz mono 16-bit PCM); the named params exist so tests can build the
/// invalid variants the reader must reject.
Uint8List wavBytes({
  required List<int> samples, // int16 values
  int sampleRate = 16000,
  int channels = 1,
  int bitsPerSample = 16,
  int audioFormat = 1, // 1 = PCM
  /// Insert a LIST chunk before `data`. Real files do this, and a reader that
  /// assumes data lives at a fixed offset silently reads garbage.
  bool includeListChunk = false,
  /// Declare a `data` size larger than the bytes actually present.
  int? overrideDataSize,
  /// Truncate the output to this many bytes.
  int? truncateTo,
}) {
  final dataBytes = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    dataBytes.setInt16(i * 2, samples[i], Endian.little);
  }
  final data = dataBytes.buffer.asUint8List();

  final out = BytesBuilder();
  void ascii(String s) => out.add(s.codeUnits);
  void u32(int v) {
    final b = ByteData(4)..setUint32(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }
  void u16(int v) {
    final b = ByteData(2)..setUint16(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  final listChunk = includeListChunk ? 12 : 0; // 8 header + 4 payload
  ascii('RIFF');
  u32(4 + 24 + listChunk + 8 + data.length); // 'WAVE' + fmt + list + data hdr
  ascii('WAVE');

  ascii('fmt ');
  u32(16);
  u16(audioFormat);
  u16(channels);
  u32(sampleRate);
  u32(sampleRate * channels * bitsPerSample ~/ 8); // byte rate
  u16(channels * bitsPerSample ~/ 8); // block align
  u16(bitsPerSample);

  if (includeListChunk) {
    ascii('LIST');
    u32(4);
    ascii('INFO');
  }

  ascii('data');
  u32(overrideDataSize ?? data.length);
  out.add(data);

  final bytes = out.toBytes();
  return truncateTo == null ? bytes : Uint8List.sublistView(bytes, 0, truncateTo);
}
