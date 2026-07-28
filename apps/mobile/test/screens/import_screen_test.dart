import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/model_paths.dart';
import 'package:mobile/screens/import_screen.dart';
import 'package:privoice_audio/privoice_audio.dart';
import 'package:privoice_core/privoice_core.dart';
import 'package:privoice_stt/privoice_stt.dart';

import '../fakes/fake_audio_importer.dart';
import '../fakes/fake_meeting_repository.dart';

/// Never use `pumpAndSettle` in this file: both progress states render an
/// indeterminate [LinearProgressIndicator], which animates forever, so
/// `pumpAndSettle` can never return. Bounded `pump()`s only — the same trap
/// `privacy_gate_test.dart` documents.
///
/// [pumpUntil] is the replacement. It alternates two things because neither
/// alone is enough: `runAsync` steps out of the test's fake-async zone so the
/// screen's real `dart:io` work (writing and reading the WAV) can actually
/// complete, and `pump` then renders whatever state that produced.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int tries = 100,
}) async {
  for (var i = 0; i < tries && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump();
  }
}

void main() {
  const model = SttModelPaths(
    encoder: 'e.onnx',
    decoder: 'd.onnx',
    joiner: 'j.onnx',
    tokens: 't.txt',
  );

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('import_screen_test');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  /// A transcriber that returns [text] as one segment without touching sherpa.
  FileTranscriber fakeTranscriber({
    String text = 'hello from the import',
    List<double> progress = const [1.0],
  }) {
    return (paths, wavPath, {onProgress}) async {
      for (final f in progress) {
        onProgress?.call(f);
      }
      return Transcript.fromSegments(
        [TranscriptSegment(text: text, startSec: 0, endSec: 2)],
        const Duration(seconds: 2),
      );
    };
  }

  Widget host({
    required MeetingRepository repository,
    required AudioImporter importer,
    FileTranscriber? transcriber,
    SttModelResolver? locateModel,
    required Directory workDir,
  }) {
    return MaterialApp(
      home: ImportScreen(
        repository: repository,
        sourcePath: '/does/not/matter/source.m4a',
        importer: importer,
        transcriber: transcriber ?? fakeTranscriber(),
        locateModel: locateModel ?? (() async => model),
        workDir: () async => workDir,
      ),
    );
  }

  testWidgets('holds the converting state while the transcode is in flight',
      (tester) async {
    final gate = Completer<void>();
    final importer = FakeAudioImporter(gate: gate);

    await tester.pumpWidget(host(
      repository: FakeMeetingRepository(),
      importer: importer,
      workDir: tmp,
    ));
    // Let the post-frame callback fire and _run() reach the gated transcode.
    await pumpUntil(tester, () => importer.calls == 1);

    expect(find.text('Converting audio…'), findsOneWidget);
    expect(find.textContaining('Transcribing'), findsNothing);
    expect(importer.calls, 1);

    // Release the gate so no future is left dangling at test end.
    gate.complete();
    await tester.pump();
    await tester.pump();
  });

  testWidgets('a decode failure shows the importer message and a retry',
      (tester) async {
    final repo = FakeMeetingRepository();
    await tester.pumpWidget(host(
      repository: repo,
      importer: FakeAudioImporter(
        failWith: const AudioImportException("That video has no audio track."),
      ),
      workDir: tmp,
    ));
    await pumpUntil(tester, () => find.text('Try again').evaluate().isNotEmpty);

    expect(find.text("Couldn't import that file"), findsOneWidget);
    expect(find.text('That video has no audio track.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(await repo.all(), isEmpty);
  });

  testWidgets('a missing speech model is reported, not treated as a bad file',
      (tester) async {
    final repo = FakeMeetingRepository();
    await tester.pumpWidget(host(
      repository: repo,
      importer: FakeAudioImporter(),
      locateModel: () async => null,
      workDir: tmp,
    ));
    await pumpUntil(tester, () => find.text('Try again').evaluate().isNotEmpty);

    expect(find.textContaining('speech model is not ready'), findsOneWidget);
    expect(await repo.all(), isEmpty);
    // The partial WAV must not survive a failed import.
    expect(tmp.listSync(), isEmpty);
  });

  testWidgets('a successful import persists a done Meeting and pops true',
      (tester) async {
    final repo = FakeMeetingRepository();
    bool? popped;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            popped = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => ImportScreen(
                  repository: repo,
                  sourcePath: '/does/not/matter/source.m4a',
                  importer: FakeAudioImporter(seconds: 3),
                  transcriber: fakeTranscriber(text: 'the quarterly review'),
                  locateModel: () async => model,
                  workDir: () async => tmp,
                ),
              ),
            );
          },
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await pumpUntil(tester, () => popped != null);

    expect(popped, isTrue);
    final saved = (await repo.all()).single;
    expect(saved.transcript, 'the quarterly review');
    expect(saved.status, MeetingStatus.done);
    // durationMs comes from WavReader reading the real WAV the fake wrote.
    expect(saved.durationMs, 3000);
    // The converted WAV is kept as the meeting's audio, like a recording.
    expect(File(saved.audioPath).existsSync(), isTrue);
  });
}
