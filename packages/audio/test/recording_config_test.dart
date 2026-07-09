import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_audio/privoice_audio.dart';

void main() {
  test('defaults to 16kHz mono wav', () {
    const cfg = RecordingConfig();
    expect(cfg.sampleRate, 16000);
    expect(cfg.numChannels, 1);
  });

  test('fileName is deterministic from timestamp', () {
    const cfg = RecordingConfig();
    final name = cfg.fileName(DateTime.fromMillisecondsSinceEpoch(1720000000000));
    expect(name, 'meeting_1720000000000.wav');
  });
}
