import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/ai_service.dart';
import 'package:mobile/model_manager.dart';
import 'package:mobile/screens/home_screen.dart';
import 'package:privoice_core/privoice_core.dart';
import 'package:privoice_models/privoice_models.dart';

import 'fakes/fake_ai_engine.dart';
import 'fakes/fake_meeting_repository.dart';
import 'fakes/fake_model_downloader.dart';

/// Counts any attempt to create a Dart HTTP client.
class _CountingHttpOverrides extends HttpOverrides {
  int count = 0;
  final List<String> where = [];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    count++;
    where.add(StackTrace.current.toString().split('\n').take(4).join(' | '));
    return super.createHttpClient(context);
  }
}

/// Privacy gate (Dart layer): the core offline flow — browse meetings, open one,
/// render cached minutes (no button tap) — must not create any HTTP client.
/// Guards against an online tier / analytics / telemetry accidentally firing
/// while offline.
///
/// The OS-level airplane-mode check (native traffic) is the on-device / Test Lab
/// complement; native STT/LLM make no network calls by design.
void main() {
  late _CountingHttpOverrides overrides;
  HttpOverrides? previous;

  setUp(() {
    previous = HttpOverrides.current;
    overrides = _CountingHttpOverrides();
    HttpOverrides.global = overrides;
  });

  tearDown(() => HttpOverrides.global = previous);

  testWidgets('offline flow creates zero HTTP clients', (tester) async {
    final meeting = Meeting(
      id: 1,
      title: 'Product sync',
      createdAt: DateTime(2026, 7, 10),
      audioPath: '',
      durationMs: 60000,
      transcript: 'Alice: ship the beta Friday. Bob: finish login Thursday.',
      // No cached minutes: opening the meeting must run the on-device
      // auto-generate pass (minutes -> action items -> title) entirely
      // offline — the strongest form of this privacy assertion.
    );

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        repository: FakeMeetingRepository([meeting]),
        ai: AiService(engine: FakeAiEngine()),
        themeMode: ValueNotifier(ThemeMode.system),
        modelManager: ModelManager(
          downloader: FakeModelDownloader(installed: {
            ModelCatalog.parakeetStt.id,
            ModelCatalog.llama1b.id,
          }),
        )..markAllReadyForTest(),
      ),
    ));
    await tester.pumpAndSettle();

    // Open the meeting; auto-generate fires on the default Overview tab.
    await tester.tap(find.text('Product sync'));
    // Bounded pumps instead of pumpAndSettle: while the auto-generate pass
    // is busy, the generating view's pulsing sparkle animates forever, which
    // would make pumpAndSettle hang. FakeAiEngine resolves via microtasks
    // (no real timers), so a handful of pumps drains the pass and lets the
    // finite entrance animations finish too.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(MarkdownBody), findsOneWidget,
        reason: 'auto-generated minutes must actually render so the privacy assertion is meaningful');

    expect(
      overrides.count,
      0,
      reason: 'Offline flow must make no network calls. Attempts:\n'
          '${overrides.where.join('\n')}',
    );
  });
}
