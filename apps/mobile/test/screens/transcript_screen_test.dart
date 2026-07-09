import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/ai_service.dart';
import 'package:mobile/screens/transcript_screen.dart';
import 'package:privoice_core/privoice_core.dart';

import '../fakes/fake_ai_engine.dart';
import '../fakes/fake_meeting_repository.dart';

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
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Action items'));
    await tester.pumpAndSettle();

    expect(find.text('Alice: ship it'), findsOneWidget);
  });
}
