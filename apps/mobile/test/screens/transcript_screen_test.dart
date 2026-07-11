import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/ai_service.dart';
import 'package:mobile/model_manager.dart';
import 'package:mobile/screens/transcript_screen.dart';
import 'package:privoice_core/privoice_core.dart';
import 'package:privoice_models/privoice_models.dart';

import '../fakes/fake_ai_engine.dart';
import '../fakes/fake_meeting_repository.dart';
import '../fakes/fake_model_downloader.dart';

void main() {
  testWidgets('smart-action bar is present with the three actions',
      (tester) async {
    final meeting = Meeting(
      id: 1,
      title: 'Product sync',
      createdAt: DateTime(2026, 7, 10),
      audioPath: '',
      durationMs: 60000,
      transcript: 'Alice: ship the beta Friday.',
    );
    await tester.pumpWidget(MaterialApp(
      home: TranscriptScreen(
        meeting: meeting,
        repository: FakeMeetingRepository([meeting]),
        ai: AiService(engine: FakeAiEngine()),
        modelManager: ModelManager(
          downloader: FakeModelDownloader(installed: {
            ModelCatalog.parakeetStt.id,
            ModelCatalog.llama1b.id,
          }),
        )..markAllReadyForTest(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Summarize'), findsOneWidget);
    expect(find.text('Action items'), findsOneWidget);
    expect(find.text('Ask'), findsOneWidget);
  });

  testWidgets('Summarize generates and renders minutes', (tester) async {
    final meeting = Meeting(
      id: 1,
      title: 'Product sync',
      createdAt: DateTime(2026, 7, 10),
      audioPath: '',
      durationMs: 60000,
      transcript: 'Alice: ship the beta Friday.',
    );
    final repo = FakeMeetingRepository([meeting]);
    await tester.pumpWidget(MaterialApp(
      home: TranscriptScreen(
        meeting: meeting,
        repository: repo,
        ai: AiService(engine: FakeAiEngine(minutes: '### Summary\nAll good.')),
        modelManager: ModelManager(
          downloader: FakeModelDownloader(installed: {
            ModelCatalog.parakeetStt.id,
            ModelCatalog.llama1b.id,
          }),
        )..markAllReadyForTest(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Summarize'));
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownBody), findsOneWidget);
    // persisted
    final saved = await repo.byId(1);
    expect(saved?.minutes, contains('All good.'));
  });

  testWidgets('Action items renders chips', (tester) async {
    final meeting = Meeting(
      id: 1,
      title: 'Product sync',
      createdAt: DateTime(2026, 7, 10),
      audioPath: '',
      durationMs: 60000,
      transcript: 'Alice: ship the beta Friday.',
    );
    await tester.pumpWidget(MaterialApp(
      home: TranscriptScreen(
        meeting: meeting,
        repository: FakeMeetingRepository([meeting]),
        ai: AiService(engine: FakeAiEngine(items: ['Alice: ship it'])),
        modelManager: ModelManager(
          downloader: FakeModelDownloader(installed: {
            ModelCatalog.parakeetStt.id,
            ModelCatalog.llama1b.id,
          }),
        )..markAllReadyForTest(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Action items'));
    await tester.pumpAndSettle();

    expect(find.text('Alice: ship it'), findsOneWidget);
  });

  testWidgets('AI actions disabled with hint until LLM ready', (tester) async {
    final meeting = Meeting(
      id: 1,
      title: 'Product sync',
      createdAt: DateTime(2026, 7, 10),
      audioPath: '',
      durationMs: 60000,
      transcript: 'Alice: ship the beta Friday.',
    );
    await tester.pumpWidget(MaterialApp(
      home: TranscriptScreen(
        meeting: meeting,
        repository: FakeMeetingRepository([meeting]),
        ai: AiService(engine: FakeAiEngine()),
        modelManager: ModelManager(downloader: FakeModelDownloader()), // not ready
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Preparing AI…'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(of: find.text('Summarize'), matching: find.byType(FilledButton)),
    );
    expect(button.onPressed, isNull); // disabled
  });

  testWidgets('duplicate action items render without a duplicate-key crash',
      (tester) async {
    final meeting = Meeting(
      id: 1,
      title: 'Product sync',
      createdAt: DateTime(2026, 7, 10),
      audioPath: '',
      durationMs: 60000,
      transcript: 'Alice: ship the beta Friday.',
    );
    await tester.pumpWidget(MaterialApp(
      home: TranscriptScreen(
        meeting: meeting,
        repository: FakeMeetingRepository([meeting]),
        // The on-device LLM sometimes emits the same action item twice.
        ai: AiService(engine: FakeAiEngine(items: const ['Ship it', 'Ship it'])),
        modelManager: ModelManager(
          downloader: FakeModelDownloader(installed: {
            ModelCatalog.parakeetStt.id,
            ModelCatalog.llama1b.id,
          }),
        )..markAllReadyForTest(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Action items'));
    await tester.pumpAndSettle();

    // Must not throw "Multiple widgets used the same GlobalKey / duplicate keys".
    expect(tester.takeException(), isNull);
    expect(find.text('Ship it'), findsNWidgets(2));
  });
}
