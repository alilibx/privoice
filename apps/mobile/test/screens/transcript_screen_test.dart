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
      title: 'Product sync',
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
  await tester.pumpAndSettle();
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
}
