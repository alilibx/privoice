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

  testWidgets('offers an Import action', (tester) async {
    await tester.pumpWidget(host(FakeMeetingRepository(), manager: readyManager()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Import'), findsOneWidget);
  });

  testWidgets('tapping import while STT not ready shows a snackbar',
      (tester) async {
    await tester.pumpWidget(host(FakeMeetingRepository(),
        manager: ModelManager(downloader: FakeModelDownloader())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Import'));
    await tester.pump();
    // Gating here rather than inside ImportScreen matters: without it the user
    // picks a file and waits out a full transcode before being told the model
    // was never ready. It also keeps the file picker from opening at all, so no
    // full-size cache copy of their recording is made for nothing.
    expect(find.textContaining('Speech-to-text'), findsOneWidget);
  });

  group('deleting a meeting collects its audio', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('home_audio');
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    /// A meeting whose audio is a real file named `meeting_<stamp>.wav` in
    /// [dir] — i.e. a name `MeetingAudioStore` actually considers.
    (Meeting, File) seededAs(String title, int stamp, DateTime at) {
      final file = File(p.join(dir.path, 'meeting_$stamp.wav'))
        ..writeAsStringSync('x');
      return (
        Meeting(
          title: title,
          createdAt: at,
          audioPath: file.path,
          durationMs: 60000,
          transcript: 'daily sync',
        ),
        file,
      );
    }

    /// A meeting whose audio is a real file in [dir].
    (Meeting, File) seeded() =>
        seededAs('Standup', 1000, DateTime(2026, 7, 10, 9));

    /// Pumps for a bounded stretch without gating on anything, so that any
    /// filesystem work a *wrong* implementation would do gets a fair chance to
    /// land before a "this file must still exist" assertion runs. Without this
    /// such an assertion could pass merely by winning a race.
    Future<void> soak(WidgetTester tester, {int rounds = 20}) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    /// Dismisses [title]'s row and waits until its undo window is really
    /// running: the row gone from the list, then the SnackBar animated in and
    /// its auto-dismiss timer armed.
    ///
    /// The second half matters. `ScaffoldMessengerState.build` arms that timer
    /// only on a frame where the entry animation has already *completed*, so a
    /// caller that jumps the clock too early elapses past nothing and then
    /// waits a further full duration for a timer armed at the far end of the
    /// jump. Measured here: the SnackBar first appears ~400ms after the row
    /// goes (Dismissible's resize, then `_delete`'s `await repository.delete`),
    /// and needs 250ms more to finish animating in — so this pumps a
    /// deliberately generous 1.5s of small frames. It is all fake-clock time,
    /// so it is exact, not a sleep.
    Future<void> dismiss(WidgetTester tester, String title) async {
      await tester.fling(find.text(title), const Offset(-500, 0), 1000);
      await pumpUntil(tester, () => find.text(title).evaluate().isEmpty,
          reason: '"$title" was never dismissed');
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
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

      // The undo window is an explicit 10s (see `HomeScreen._delete`, which
      // lengthens it because `persist: false` also opts out of Flutter's
      // no-timeout-under-a-screen-reader exemption); run past it, then let
      // collection land.
      await tester.pump(const Duration(seconds: 11));
      await pumpUntil(tester, () => !file.existsSync(),
          reason: 'the orphaned audio was never collected');

      expect(file.existsSync(), isFalse);
    });

    // The two regression tests below encode why collection from Home must be
    // *targeted* at the one file whose row was just deleted, rather than a
    // global sweep. `_delete`'s continuation resumes when the SnackBar closes,
    // and `_HomeScreenState` stays mounted the whole time — so that moment is
    // not quiescent: a capture may be in flight, or another delete's undo
    // window may still be open. A global sweep at that moment deletes files it
    // has no business touching. Both were reproduced before the fix.

    testWidgets('a second delete keeps its audio while its own Undo is live',
        (tester) async {
      final (a, fileA) = seededAs('Standup', 1000, DateTime(2026, 7, 10, 9));
      final (b, fileB) =
          seededAs('Design review', 2000, DateTime(2026, 7, 10, 11));
      await tester.pumpWidget(hostWithStore(FakeMeetingRepository([a, b])));
      await tester.pumpAndSettle();

      // Two deletes in quick succession. SnackBars queue FIFO, so B's Undo is
      // still pending (unshown, then shown) while A's window runs out — and by
      // then *both* rows are already gone from the repository.
      await dismiss(tester, 'Standup');
      await dismiss(tester, 'Design review');
      expect(fileB.existsSync(), isTrue,
          reason: 'sanity: B is deleted but its audio is not collected yet');

      // Run past A's undo window (10s) so A's continuation collects.
      await tester.pump(const Duration(seconds: 11));
      await pumpUntil(tester, () => !fileA.existsSync(),
          reason: "A's own orphaned audio was never collected");
      await soak(tester);

      expect(fileB.existsSync(), isTrue,
          reason: "A's collection must not touch B's audio — B's Undo is "
              'still offered, and tapping it would restore a row pointing at '
              'a deleted file');
    });

    testWidgets('a capture started during the undo window keeps its audio',
        (tester) async {
      final (a, fileA) = seededAs('Standup', 1000, DateTime(2026, 7, 10, 9));
      await tester.pumpWidget(hostWithStore(FakeMeetingRepository([a])));
      await tester.pumpAndSettle();

      await dismiss(tester, 'Standup');

      // Stand in for a recording (or import) that starts after the delete:
      // `AppAudioRecorder.start` creates `meeting_<ms>.wav` immediately, and
      // `RecordScreen` inserts the row only after transcription finishes, so
      // the file is legitimately unreferenced for the whole capture.
      final inFlight = File(p.join(dir.path, 'meeting_9000.wav'))
        ..writeAsStringSync('recording…');

      // Run past A's undo window (10s) so A's continuation collects.
      await tester.pump(const Duration(seconds: 11));
      await pumpUntil(tester, () => !fileA.existsSync(),
          reason: "A's own orphaned audio was never collected");
      await soak(tester);

      expect(inFlight.existsSync(), isTrue,
          reason: 'the in-flight capture is unreferenced by design; deleting '
              'it loses the recording the user is making right now');
    });
  });
}
