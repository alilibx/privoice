import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_stt/privoice_stt.dart';

import 'wav_bytes.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('wav_reader'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<String> write(List<int> bytes, {String name = 'a.wav'}) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes(bytes);
    return f.path;
  }

  test('reads a valid 16 kHz mono 16-bit header', () async {
    final path = await write(wavBytes(samples: List.filled(16000, 0)));
    final r = await WavReader.open(path);
    expect(r.sampleRate, 16000);
    expect(r.sampleCount, 16000);
    expect(r.duration, const Duration(seconds: 1));
    await r.close();
  });

  test('skips a LIST chunk before data', () async {
    // A fixed-offset reader would take the LIST payload as samples.
    final path = await write(
        wavBytes(samples: [1, 2, 3, 4], includeListChunk: true));
    final r = await WavReader.open(path);
    expect(r.sampleCount, 4);
    final w = await r.readWindow(0, 4);
    expect(w[0], closeTo(1 / 32768, 1e-9));
    await r.close();
  });

  test('rejects stereo, wrong bit depth, wrong rate, non-PCM', () async {
    Future<void> expectRejected(List<int> bytes, String name) async {
      final path = await write(bytes, name: name);
      await expectLater(
          WavReader.open(path), throwsA(isA<WavFormatException>()));
    }

    await expectRejected(
        wavBytes(samples: [0, 0], channels: 2), 'stereo.wav');
    await expectRejected(
        wavBytes(samples: [0, 0], bitsPerSample: 8), 'depth8.wav');
    await expectRejected(
        wavBytes(samples: [0, 0], sampleRate: 44100), 'rate44.wav');
    await expectRejected(
        wavBytes(samples: [0, 0], audioFormat: 3), 'float.wav');
  });

  test('rejects a truncated header and an oversized data size', () async {
    final short = await write(wavBytes(samples: [0]).sublist(0, 20), name: 't.wav');
    await expectLater(WavReader.open(short), throwsA(isA<WavFormatException>()));

    final lying =
        await write(wavBytes(samples: [0, 0], overrideDataSize: 999999), name: 'l.wav');
    await expectLater(WavReader.open(lying), throwsA(isA<WavFormatException>()));
  });

  test('rejects a file that is not RIFF/WAVE', () async {
    final path = await write(List.filled(64, 0x41), name: 'junk.wav');
    await expectLater(WavReader.open(path), throwsA(isA<WavFormatException>()));
  });

  test('readWindow reads at start, middle and the exact final sample',
      () async {
    final path = await write(wavBytes(samples: [10, 20, 30, 40, 50]));
    final r = await WavReader.open(path);

    final head = await r.readWindow(0, 2);
    expect(head.length, 2);
    expect(head[0], closeTo(10 / 32768, 1e-9));

    final mid = await r.readWindow(2, 2);
    expect(mid[0], closeTo(30 / 32768, 1e-9));

    final tail = await r.readWindow(4, 1);
    expect(tail.length, 1);
    expect(tail[0], closeTo(50 / 32768, 1e-9));
    await r.close();
  });

  test('converts int16 extremes correctly', () async {
    final path = await write(wavBytes(samples: [0, 32767, -32768]));
    final r = await WavReader.open(path);
    final w = await r.readWindow(0, 3);
    expect(w[0], 0.0);
    expect(w[1], closeTo(32767 / 32768, 1e-6));
    expect(w[2], closeTo(-1.0, 1e-9));
    await r.close();
  });

  test('a window past the end throws instead of returning garbage', () async {
    final path = await write(wavBytes(samples: [1, 2, 3]));
    final r = await WavReader.open(path);
    await expectLater(r.readWindow(2, 5), throwsA(isA<RangeError>()));
    await expectLater(r.readWindow(-1, 1), throwsA(isA<RangeError>()));
    await r.close();
  });
}
