import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/ai_service.dart';
import 'package:mobile/model_manager.dart';
import 'package:mobile/screens/home_screen.dart';
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

void main() {
  ModelManager readyManager() => ModelManager(
        downloader: FakeModelDownloader(installed: {
          ModelCatalog.parakeetStt.id,
          ModelCatalog.llama1b.id,
        }),
      )..markAllReadyForTest();

  testWidgets('shows setup banner while models not ready', (tester) async {
    final m = ModelManager(downloader: FakeModelDownloader()); // nothing ready
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        repository: FakeMeetingRepository(),
        ai: AiService(),
        themeMode: ValueNotifier(ThemeMode.system),
        modelManager: m,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Setting up'), findsOneWidget);
  });

  testWidgets('tapping Record while STT not ready shows a snackbar, no push',
      (tester) async {
    final m = ModelManager(downloader: FakeModelDownloader());
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        repository: FakeMeetingRepository(),
        ai: AiService(),
        themeMode: ValueNotifier(ThemeMode.system),
        modelManager: m,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(); // let the snackbar appear
    expect(find.textContaining('Speech-to-text'), findsOneWidget);
  });

  testWidgets('no banner when all models ready', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        repository: FakeMeetingRepository(),
        ai: AiService(),
        themeMode: ValueNotifier(ThemeMode.system),
        modelManager: readyManager(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Setting up'), findsNothing);
  });
  testWidgets('shows empty state when there are no meetings', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(repository: FakeMeetingRepository(), ai: AiService(), themeMode: ValueNotifier(ThemeMode.system)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No meetings yet'), findsOneWidget);
    expect(find.text('Record'), findsOneWidget);
  });

  testWidgets('lists meetings, newest first', (tester) async {
    final repo = FakeMeetingRepository([
      _m('Standup', 'daily sync', DateTime(2026, 7, 10, 9)),
      _m('Design review', 'ui discussion', DateTime(2026, 7, 10, 11)),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(repository: repo, ai: AiService(), themeMode: ValueNotifier(ThemeMode.system)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Standup'), findsOneWidget);
    expect(find.text('Design review'), findsOneWidget);
  });

  testWidgets('search filters the list', (tester) async {
    final repo = FakeMeetingRepository([
      _m('Standup', 'daily sync', DateTime(2026, 7, 10, 9)),
      _m('Design review', 'ui discussion', DateTime(2026, 7, 10, 11)),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(repository: repo, ai: AiService(), themeMode: ValueNotifier(ThemeMode.system)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'design');
    await tester.pumpAndSettle();

    expect(find.text('Design review'), findsOneWidget);
    expect(find.text('Standup'), findsNothing);
  });
}
