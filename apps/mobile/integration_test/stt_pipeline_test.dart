import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:privoice_stt/privoice_stt.dart';

/// On-device functional test of the real sherpa-onnx Parakeet pipeline.
///
/// Prereq: the model + a sample WAV must be pushed to the app's external files
/// dir before running (see tools/emulator-stt-test.sh). This proves the native
/// STT path works end-to-end. NOTE: timing on an emulator is NOT representative
/// of real phone performance — treat RTF here as functional, not a verdict.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('on-device STT transcribes a sample WAV (Parakeet-TDT v3)',
      (tester) async {
    final ext = await getExternalStorageDirectory();
    expect(ext, isNotNull, reason: 'external storage should exist on Android');

    final modelDir = p.join(ext!.path, 'models', 'parakeet-tdt-v3-int8');
    final wavPath = p.join(modelDir, 'test_wavs', 'en.wav');

    expect(File(p.join(modelDir, 'encoder.int8.onnx')).existsSync(), isTrue,
        reason: 'model not pushed — run tools/emulator-stt-test.sh first');
    expect(File(wavPath).existsSync(), isTrue,
        reason: 'sample WAV not pushed');

    final engine = SherpaSttEngine();
    await engine.init(SttModelPaths(
      encoder: p.join(modelDir, 'encoder.int8.onnx'),
      decoder: p.join(modelDir, 'decoder.int8.onnx'),
      joiner: p.join(modelDir, 'joiner.int8.onnx'),
      tokens: p.join(modelDir, 'tokens.txt'),
    ));

    final sw = Stopwatch()..start();
    final transcript = await engine.transcribe(wavPath);
    sw.stop();

    final rtf = sw.elapsedMilliseconds / transcript.audioDuration.inMilliseconds;
    // ignore: avoid_print
    print('ITEST_STT rtf=${rtf.toStringAsFixed(2)} '
        'audioMs=${transcript.audioDuration.inMilliseconds} '
        'transcribeMs=${sw.elapsedMilliseconds} '
        'text="${transcript.fullText}"');

    expect(transcript.fullText.trim(), isNotEmpty,
        reason: 'transcription should produce text');

    await engine.dispose();
  });
}
