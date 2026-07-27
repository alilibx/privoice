import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:privoice_audio/privoice_audio.dart';

void main() {
  // These two guards are pure dart:io logic that runs before any call into
  // the native decoder, so they can be verified with a real path and a real
  // exception — no mocking of AudioDecoder.convertToWav, which would only
  // assert we call the function we obviously call.
  group('AudioDecoderImporter guards', () {
    const importer = AudioDecoderImporter();

    test('a nonexistent sourcePath throws AudioImportException', () async {
      final dir = await Directory.systemTemp.createTemp('audio_import_test');
      addTearDown(() => dir.delete(recursive: true));

      final missing = p.join(dir.path, 'does_not_exist.m4a');
      final target = p.join(dir.path, 'out.wav');

      await expectLater(
        importer.toSttWav(sourcePath: missing, targetPath: target),
        throwsA(isA<AudioImportException>()),
      );
    });

    test('sourcePath == targetPath throws AudioImportException without '
        'touching the file', () async {
      final dir = await Directory.systemTemp.createTemp('audio_import_test');
      addTearDown(() => dir.delete(recursive: true));

      final samePath = p.join(dir.path, 'recording.m4a');
      final source = File(samePath);
      await source.writeAsString('not a real audio file, just a sentinel');

      await expectLater(
        importer.toSttWav(sourcePath: samePath, targetPath: samePath),
        throwsA(isA<AudioImportException>()),
      );

      // The whole point of the guard: the file must survive untouched.
      expect(await source.exists(), isTrue);
      expect(
        await source.readAsString(),
        'not a real audio file, just a sentinel',
      );
    });
  });
}
