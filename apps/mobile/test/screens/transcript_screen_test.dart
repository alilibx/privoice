import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/ai_service.dart';
import 'package:mobile/model_manager.dart';
import 'package:mobile/screens/transcript_screen.dart';
import 'package:privoice_core/privoice_core.dart';
import 'package:privoice_models/privoice_models.dart';

import '../fakes/fake_ai_engine.dart';
import '../fakes/fake_meeting_repository.dart';
import '../fakes/fake_model_downloader.dart';

Meeting _meeting({String? minutes, List<ActionItem> items = const []}) => Meeting(
      id: 1,
      // Default-shaped title (record_screen._defaultTitle()) so the
      // auto-generate pass's title-upgrade guard applies in tests too.
      title: 'Meeting 10/7 09:00',
      createdAt: DateTime(2026, 7, 10),
      audioPath: '',
      durationMs: 60000,
      transcript: 'Alice: ship the beta Friday.',
      minutes: minutes,
      actionItems: items,
    );

ModelManager _ready() => ModelManager(
      downloader: FakeModelDownloader(installed: {
        ModelCatalog.parakeetStt.id,
        ModelCatalog.llama1b.id,
      }),
    )..markAllReadyForTest();

Future<void> _pump(WidgetTester tester,
    {required Meeting meeting,
    required MeetingRepository repo,
    FakeAiEngine? engine,
    ModelManager? manager}) async {
  await tester.pumpWidget(MaterialApp(
    home: TranscriptScreen(
      meeting: meeting,
      repository: repo,
      ai: AiService(engine: engine ?? FakeAiEngine()),
      modelManager: manager ?? _ready(),
    ),
  ));
  // Bounded pumps instead of pumpAndSettle: the busy view's pulsing sparkle
  // and the "preparing" state's indeterminate LinearProgressIndicator both
  // repeat forever, which would make pumpAndSettle hang. FakeAiEngine
  // resolves via microtasks (no real timers), so a handful of pumps drains
  // the auto-generate pass and lets the finite entrance animations
  // (chips/reveal, <= ~700ms) finish too.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('opens on Overview with Overview + Transcript tabs',
      (tester) async {
    final m = _meeting(minutes: '### Summary\nAll good.');
    await _pump(tester, meeting: m, repo: FakeMeetingRepository([m]));

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Transcript'), findsOneWidget);
    // Overview is the default tab: cached minutes are visible.
    expect(find.textContaining('All good.'), findsWidgets);
  });

  testWidgets('persistent Ask entry is present', (tester) async {
    final m = _meeting(minutes: '### Summary\nx');
    await _pump(tester, meeting: m, repo: FakeMeetingRepository([m]));
    expect(find.text('Ask about this meeting…'), findsOneWidget);
  });

  testWidgets('Ask entry reacts to model becoming ready without a rebuild',
      (tester) async {
    final m = _meeting(minutes: '### Summary\nx');
    final manager = ModelManager(downloader: FakeModelDownloader());
    await _pump(tester, meeting: m, repo: FakeMeetingRepository([m]), manager: manager);

    InkWell askInkWell() => tester.widget<InkWell>(find.ancestor(
        of: find.text('Ask about this meeting…'),
        matching: find.byType(InkWell)));

    expect(askInkWell().onTap, isNull);

    manager.markAllReadyForTest();
    await tester.pump();

    expect(askInkWell().onTap, isNotNull);
  });

  testWidgets('overflow menu offers share options and a disabled Export',
      (tester) async {
    final m = _meeting(minutes: '### Summary\nx');
    await _pump(tester, meeting: m, repo: FakeMeetingRepository([m]));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Share minutes'), findsOneWidget);
    expect(find.text('Copy all'), findsOneWidget);
    final export = tester.widget<PopupMenuItem<String>>(
      find.widgetWithText(PopupMenuItem<String>, 'Export (coming soon)'),
    );
    expect(export.enabled, isFalse);
  });

  testWidgets('menu shows Share action items and Copy all', (tester) async {
    final m = _meeting(
        minutes: '### Summary\nx', items: const [ActionItem(text: 'Ship it')]);
    await _pump(tester, meeting: m, repo: FakeMeetingRepository([m]));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Share action items'), findsOneWidget);
    expect(find.text('Copy all'), findsOneWidget);
  });

  testWidgets('auto-generates minutes + items + title on open, once',
      (tester) async {
    final m = _meeting(); // no minutes
    final repo = FakeMeetingRepository([m]);
    final engine = FakeAiEngine(
      minutes: '### Summary\nGenerated once.',
      items: const ['Ship it'],
      titleText: 'Beta Launch Sync',
    );
    await _pump(tester, meeting: m, repo: repo, engine: engine);

    expect(find.textContaining('Generated once.'), findsWidgets);
    expect(find.text('Ship it'), findsOneWidget);

    final saved = await repo.byId(1);
    expect(saved?.minutes, contains('Generated once.'));
    expect(saved?.actionItems.map((a) => a.text), ['Ship it']);
    // Default title was auto-upgraded.
    expect(saved?.title, 'Beta Launch Sync');
  });

  testWidgets('auto-generate runs the summarize pass exactly once',
      (tester) async {
    final m = _meeting(); // no minutes
    final repo = FakeMeetingRepository([m]);
    final engine = _CountingAiEngine();
    await _pump(tester, meeting: m, repo: repo, engine: engine);

    // Proves single-shot across the multiple rebuilds _maybeAutoGenerate
    // sees (ListenableBuilder + setState during the pass), not just that
    // the final state looks right.
    expect(engine.summarizeCalls, 1);
  });

  testWidgets('non-default title is never overwritten by auto-title',
      (tester) async {
    final m = Meeting(
      id: 1,
      title: 'Kept Name',
      createdAt: DateTime(2026, 7, 10),
      audioPath: '',
      durationMs: 60000,
      transcript: 'Alice: ship the beta Friday.',
      minutes: null,
      actionItems: const [],
    );
    final repo = FakeMeetingRepository([m]);
    final engine = FakeAiEngine(titleText: 'AI Title');
    await _pump(tester, meeting: m, repo: repo, engine: engine);

    final saved = await repo.byId(1);
    // Title guard held: a non-default title is never overwritten.
    expect(saved?.title, 'Kept Name');
    // Sanity: minutes were still generated by the pass.
    expect(saved?.minutes, isNotNull);
    expect(saved?.minutes, isNotEmpty);
  });

  testWidgets(
      'shows an in-place Retry control when the first auto-generate fails',
      (tester) async {
    final m = _meeting(); // no minutes -> auto-generate kicks in
    final repo = FakeMeetingRepository([m]);
    await _pump(
      tester,
      meeting: m,
      repo: repo,
      engine: _ThrowingAiEngine(),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('does not auto-run when minutes already cached', (tester) async {
    final m = _meeting(minutes: '### Summary\nCached.');
    final repo = FakeMeetingRepository([m]);
    final engine = _CountingAiEngine();
    await _pump(tester, meeting: m, repo: repo, engine: engine);

    expect(engine.summarizeCalls, 0);
  });

  testWidgets('shows Preparing AI hold when LLM not ready', (tester) async {
    final m = _meeting();
    await _pump(
      tester,
      meeting: m,
      repo: FakeMeetingRepository([m]),
      manager: ModelManager(downloader: FakeModelDownloader()), // not ready
    );
    expect(find.textContaining('Preparing on-device AI'), findsOneWidget);
  });

  testWidgets('checking an action item persists done and survives rebuild',
      (tester) async {
    final m = _meeting(
      minutes: '### Summary\nx',
      items: const [ActionItem(text: 'Ship it'), ActionItem(text: 'Email Bob')],
    );
    final repo = FakeMeetingRepository([m]);
    await _pump(tester, meeting: m, repo: repo);

    // Tick the first item.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    final saved = await repo.byId(1);
    final shipIt = saved!.actionItems.firstWhere((a) => a.text == 'Ship it');
    expect(shipIt.done, isTrue);
  });

  testWidgets('tapping the title renames the meeting', (tester) async {
    final m = _meeting(minutes: '### Summary\nx');
    final repo = FakeMeetingRepository([m]);
    await _pump(tester, meeting: m, repo: repo);

    // _meeting()'s default title is the default-shaped placeholder
    // ('Meeting 10/7 09:00'), not a real title — tap that.
    await tester.tap(find.text('Meeting 10/7 09:00'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Renamed Meeting');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Renamed Meeting'), findsOneWidget);
    expect((await repo.byId(1))?.title, 'Renamed Meeting');
  });

  testWidgets('tapping Cancel in the rename dialog keeps the original title',
      (tester) async {
    final m = _meeting(minutes: '### Summary\nx');
    final repo = FakeMeetingRepository([m]);
    await _pump(tester, meeting: m, repo: repo);

    await tester.tap(find.text('Meeting 10/7 09:00'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Should Not Save');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Meeting 10/7 09:00'), findsOneWidget);
    expect((await repo.byId(1))?.title, 'Meeting 10/7 09:00');
  });

  testWidgets(
      'streaming callbacks after the screen is disposed do not throw',
      (tester) async {
    final m = _meeting(); // no minutes -> auto-generate kicks in
    final repo = FakeMeetingRepository([m]);
    final engine = _CompleterAiEngine();
    await tester.pumpWidget(MaterialApp(
      home: TranscriptScreen(
        meeting: m,
        repository: repo,
        ai: AiService(engine: engine),
        modelManager: _ready(),
      ),
    ));
    // Let the post-frame auto-generate callback fire and call
    // engine.summarize, which captures onToken/onProgress and then hangs
    // (via the uncompleted Completer) so generation is still "in flight".
    await tester.pump();
    await tester.pump();
    expect(engine.capturedOnToken, isNotNull);
    expect(engine.capturedOnProgress, isNotNull);

    // Navigate away, disposing the TranscriptScreen's State while the
    // summarize() future is still pending.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    // Simulate late tokens/progress arriving from the still-running
    // on-device generation after disposal. Without the `mounted` guard in
    // transcript_screen.dart's _generateOverview, these would call setState
    // on a disposed State and throw.
    engine.capturedOnToken!('late token after dispose');
    engine.capturedOnProgress!(0.5);

    expect(tester.takeException(), isNull);
  });
}

/// [FakeAiEngine.summarize] that captures the streaming callbacks and never
/// resolves on its own, so a test can dispose the caller mid-generation and
/// then invoke the callbacks manually to check for the `mounted` guard.
class _CompleterAiEngine extends FakeAiEngine {
  void Function(String)? capturedOnToken;
  void Function(double)? capturedOnProgress;
  final _summarizeCompleter = Completer<String>();

  @override
  Future<String> summarize(
    String transcript, {
    String? userInstructions,
    void Function(String partial)? onToken,
    void Function(double)? onProgress,
  }) {
    capturedOnToken = onToken;
    capturedOnProgress = onProgress;
    return _summarizeCompleter.future;
  }
}

class _CountingAiEngine extends FakeAiEngine {
  int summarizeCalls = 0;
  @override
  Future<String> summarize(String transcript,
      {String? userInstructions,
      void Function(String partial)? onToken,
      void Function(double)? onProgress}) async {
    summarizeCalls++;
    return super.summarize(transcript,
        userInstructions: userInstructions, onToken: onToken, onProgress: onProgress);
  }
}

class _ThrowingAiEngine extends FakeAiEngine {
  @override
  Future<String> summarize(String transcript,
      {String? userInstructions,
      void Function(String partial)? onToken,
      void Function(double)? onProgress}) async {
    throw Exception('boom');
  }
}
