import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:privoice_audio/privoice_audio.dart';

/// Writes a real, valid 16 kHz mono 16-bit WAV so the import flow can be
/// tested end to end without invoking native decoders.
class FakeAudioImporter implements AudioImporter {
  FakeAudioImporter({
    this.seconds = 2,
    this.failWith,
    this.failTimes,
    this.gate,
  });

  final int seconds;

  /// When set, [toSttWav] throws this instead of writing a file.
  final AudioImportException? failWith;

  /// Limits [failWith] to the first N calls, so a test can exercise a retry
  /// that succeeds. Null means every call fails.
  final int? failTimes;

  /// When set, [toSttWav] waits on this before doing anything, so a test can
  /// hold the caller in its "converting" state and assert on it.
  final Completer<void>? gate;

  int calls = 0;

  @override
  Future<void> toSttWav({
    required String sourcePath,
    required String targetPath,
  }) async {
    calls++;
    final hold = gate;
    if (hold != null) await hold.future;
    final fail = failWith;
    final limit = failTimes;
    if (fail != null && (limit == null || calls <= limit)) throw fail;

    const sampleRate = 16000;
    final samples = sampleRate * seconds;
    final data = ByteData(samples * 2); // all zeros: silence is fine here
    final out = BytesBuilder();
    void ascii(String s) => out.add(s.codeUnits);
    void u32(int v) =>
        out.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
    void u16(int v) =>
        out.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());

    ascii('RIFF');
    u32(36 + data.lengthInBytes);
    ascii('WAVE');
    ascii('fmt ');
    u32(16);
    u16(1);
    u16(1);
    u32(sampleRate);
    u32(sampleRate * 2);
    u16(2);
    u16(16);
    ascii('data');
    u32(data.lengthInBytes);
    out.add(data.buffer.asUint8List());

    await File(targetPath).writeAsBytes(out.toBytes());
  }
}
