import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/ai_service.dart';
import 'package:mobile/model_manager.dart';
import 'package:mobile/screens/home_screen.dart';
import 'package:path/path.dart' as p;
import 'package:privoice_core/privoice_core.dart';
import 'package:privoice_models/privoice_models.dart';

import '../fakes/fake_meeting_repository.dart';
import '../fakes/fake_model_downloader.dart';

Meeting _m(String title, String transcript, DateTime at) => Meeting(
      title: title,
      createdAt: at,
      audioPath: '',
      durationMs: 60000,
      transcript: transcript,
    );

/// `testWidgets` runs in a fake-async zone where real `dart:io` work cannot
/// complete, so pumping alone never lets a file delete land. Alternating
/// `runAsync` (real event loop) with `pump` (render) is what makes it finish.
/// Fails on exhaustion rather than returning quietly.
///
/// Deviation from the brief: the brief's literal helper calls `tester.pump()`
/// with no duration. That never advances the binding's virtual clock, so a
/// `Ticker`-driven animation (e.g. the SnackBar's dismiss `AnimationController`
/// used by both `ScaffoldMessengerState.hideCurrentSnackBar` and its
/// auto-dismiss timeout) never progresses past its first, zero-elapsed tick —
/// confirmed against the Flutter SDK sources (`scaffold.dart`,
/// `scheduler/ticker.dart`) and reproduced in an isolated scratch test outside
/// this app. A small `Duration` is passed here so real animations can
/// actually finish; this is not `pumpAndSettle` (bounded iteration count, no
/// automatic settle-loop, still gated on the `ready()` condition each pass).
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  int tries = 100,
  String? reason,
}) async {
  for (var i = 0; i < tries; i++) {
    if (ready()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (!ready()) {
    fail('pumpUntil gave up after $tries frames'
        '${reason == null ? '' : ': $reason'}');
  }
}

void main() {
  ModelManager readyManager() => ModelManager(
        downloader: FakeModelDownloader(installed: {
          ModelCatalog.parakeetStt.id,
          ModelCatalog.llama1b.id,
        }),
      )..markAllReadyForTest();

  Widget host(MeetingRepository repo, {ModelManager? manager}) => MaterialApp(
        home: HomeScreen(
          repository: repo,
          ai: AiService(),
          themeMode: ValueNotifier(ThemeMode.system),
          modelManager: manager,
        ),
      );

  testWidgets('shows setup banner while models not ready', (tester) async {
    await tester.pumpWidget(host(FakeMeetingRepository(),
        manager: ModelManager(downloader: FakeModelDownloader())));
    await tester.pumpAndSettle();
    expect(find.textContaining('Setting up'), findsOneWidget);
  });

  testWidgets('no banner when all models ready', (tester) async {
    await tester.pumpWidget(host(FakeMeetingRepository(), manager: readyManager()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Setting up'), findsNothing);
  });

  testWidgets('tapping record while STT not ready shows a snackbar', (tester) async {
    await tester.pumpWidget(host(FakeMeetingRepository(),
        manager: ModelManager(downloader: FakeModelDownloader())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recordButton')));
    await tester.pump();
    expect(find.textContaining('Speech-to-text'), findsOneWidget);
  });

  testWidgets('empty repository shows the invitation and the record dock',
      (tester) async {
    await tester.pumpWidget(host(FakeMeetingRepository(), manager: readyManager()));
    await tester.pumpAndSettle();
    expect(find.textContaining('first meeting'), findsOneWidget);
    expect(find.byKey(const Key('recordButton')), findsOneWidget);
    expect(find.text('Tap to record'), findsOneWidget);
  });

  testWidgets('lists meetings grouped', (tester) async {
    final repo = FakeMeetingRepository([
      _m('Standup', 'daily sync', DateTime(2026, 7, 10, 9)),
      _m('Design review', 'ui discussion', DateTime(2026, 7, 10, 11)),
    ]);
    await tester.pumpWidget(host(repo, manager: readyManager()));
    await tester.pumpAndSettle();
    expect(find.text('Standup'), findsOneWidget);
    expect(find.text('Design review'), findsOneWidget);
  });

  testWidgets('search filters the list', (tester) async {
    final repo = FakeMeetingRepository([
      _m('Standup', 'daily sync', DateTime(2026, 7, 10, 9)),
      _m('Design review', 'ui discussion', DateTime(2026, 7, 10, 11)),
    ]);
    await tester.pumpWidget(host(repo, manager: readyManager()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'design');
    await tester.pumpAndSettle();
    expect(find.text('Design review'), findsOneWidget);
    expect(find.text('Standup'), findsNothing);
  });

  group('deleting a meeting collects its audio', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('home_audio');
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    /// A meeting whose audio is a real file in [dir].
    (Meeting, File) seeded() {
      final file = File(p.join(dir.path, 'meeting_1000.wav'))
        ..writeAsStringSync('x');
      return (
        Meeting(
          title: 'Standup',
          createdAt: DateTime(2026, 7, 10, 9),
          audioPath: file.path,
          durationMs: 60000,
          transcript: 'daily sync',
        ),
        file,
      );
    }

    Widget hostWithStore(MeetingRepository repo) => MaterialApp(
          home: HomeScreen(
            repository: repo,
            ai: AiService(),
            themeMode: ValueNotifier(ThemeMode.system),
            modelManager: readyManager(),
            audioStore: MeetingAudioStore(dir),
          ),
        );

    testWidgets('Undo keeps the audio file', (tester) async {
      final (meeting, file) = seeded();
      await tester.pumpWidget(hostWithStore(FakeMeetingRepository([meeting])));
      await tester.pumpAndSettle();

      await tester.fling(
          find.text('Standup'), const Offset(-500, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      // Let the re-insert land, the SnackBar close, and collection run.
      await pumpUntil(tester, () => find.text('Undo').evaluate().isEmpty,
          reason: 'the SnackBar never closed');
      await pumpUntil(tester, () => find.text('Standup').evaluate().isNotEmpty,
          reason: 'the meeting was never restored');

      expect(file.existsSync(), isTrue,
          reason: 'Undo restored the meeting, so its audio must survive');
    });

    testWidgets('letting the SnackBar expire collects the audio file',
        (tester) async {
      final (meeting, file) = seeded();
      await tester.pumpWidget(hostWithStore(FakeMeetingRepository([meeting])));
      await tester.pumpAndSettle();

      await tester.fling(
          find.text('Standup'), const Offset(-500, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsOneWidget);

      // Default SnackBar duration is 4s; run past it, then let collection land.
      await tester.pump(const Duration(seconds: 5));
      await pumpUntil(tester, () => !file.existsSync(),
          reason: 'the orphaned audio was never collected');

      expect(file.existsSync(), isFalse);
    });
  });
}
