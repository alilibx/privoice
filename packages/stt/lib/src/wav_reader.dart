import 'dart:io';
import 'dart:typed_data';

/// The WAV file could not be parsed, or is not the format the STT pipeline
/// requires (16 kHz mono 16-bit PCM).
class WavFormatException implements Exception {
  const WavFormatException(this.message);
  final String message;
  @override
  String toString() => 'WavFormatException: $message';
}

/// Reads 16 kHz mono 16-bit PCM WAV in bounded windows.
///
/// Exists because `sherpa.readWave` materialises an entire file as a
/// `Float32List` — roughly 230 MB per hour of audio at this format, on top of
/// ~1.4 GB of loaded models. Nothing here ever holds more than one window.
class WavReader {
  WavReader._(this._file, this._dataOffset, this.sampleRate, this.sampleCount);

  final RandomAccessFile _file;
  final int _dataOffset;

  final int sampleRate;
  final int sampleCount;

  static const int requiredSampleRate = 16000;
  static const int requiredChannels = 1;
  static const int requiredBitsPerSample = 16;
  static const int _bytesPerSample = 2;

  Duration get duration =>
      Duration(milliseconds: (sampleCount * 1000 / sampleRate).round());

  /// Parses and validates the header. Throws [WavFormatException] on anything
  /// this pipeline cannot consume.
  static Future<WavReader> open(String path) async {
    final file = await File(path).open();
    try {
      final length = await file.length();
      if (length < 44) {
        throw const WavFormatException('File is too short to be a WAV.');
      }

      final riff = await file.read(12);
      if (String.fromCharCodes(riff.sublist(0, 4)) != 'RIFF' ||
          String.fromCharCodes(riff.sublist(8, 12)) != 'WAVE') {
        throw const WavFormatException('Not a RIFF/WAVE file.');
      }

      int? rate, channels, bits, format;
      int? dataOffset, dataSize;
      var pos = 12;

      // Walk the chunk list. `data` is NOT at a fixed offset — real files
      // carry LIST/fact chunks first.
      while (pos + 8 <= length) {
        await file.setPosition(pos);
        final header = await file.read(8);
        if (header.length < 8) break;
        final id = String.fromCharCodes(header.sublist(0, 4));
        final size = ByteData.sublistView(header, 4, 8)
            .getUint32(0, Endian.little);
        final body = pos + 8;

        if (id == 'fmt ') {
          await file.setPosition(body);
          final fmt = await file.read(16);
          if (fmt.length < 16) {
            throw const WavFormatException('Truncated fmt chunk.');
          }
          final d = ByteData.sublistView(fmt);
          format = d.getUint16(0, Endian.little);
          channels = d.getUint16(2, Endian.little);
          rate = d.getUint32(4, Endian.little);
          bits = d.getUint16(14, Endian.little);
        } else if (id == 'data') {
          dataOffset = body;
          dataSize = size;
          break; // samples start here; no need to walk further
        }

        pos = body + size + (size.isOdd ? 1 : 0); // chunks are word-aligned
      }

      if (rate == null || channels == null || bits == null || format == null) {
        throw const WavFormatException('Missing fmt chunk.');
      }
      if (dataOffset == null || dataSize == null) {
        throw const WavFormatException('Missing data chunk.');
      }
      if (format != 1) {
        throw WavFormatException('Not PCM (format $format).');
      }
      if (channels != requiredChannels) {
        throw WavFormatException('Expected mono, got $channels channels.');
      }
      if (bits != requiredBitsPerSample) {
        throw WavFormatException('Expected 16-bit, got $bits-bit.');
      }
      if (rate != requiredSampleRate) {
        throw WavFormatException('Expected ${requiredSampleRate}Hz, got ${rate}Hz.');
      }
      if (dataOffset + dataSize > length) {
        throw const WavFormatException('data chunk extends past end of file.');
      }

      return WavReader._(file, dataOffset, rate, dataSize ~/ _bytesPerSample);
    } catch (_) {
      await file.close();
      rethrow;
    }
  }

  /// Reads [count] samples from [startSample], as float in [-1.0, 1.0].
  Future<Float32List> readWindow(int startSample, int count) async {
    if (startSample < 0 || count < 0) {
      throw RangeError('Negative window ($startSample, $count).');
    }
    if (startSample + count > sampleCount) {
      throw RangeError(
          'Window ($startSample, $count) exceeds $sampleCount samples.');
    }
    await _file.setPosition(_dataOffset + startSample * _bytesPerSample);
    final raw = await _file.read(count * _bytesPerSample);
    final view = ByteData.sublistView(raw);
    final out = Float32List(count);
    for (var i = 0; i < count; i++) {
      out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  Future<void> close() => _file.close();
}
