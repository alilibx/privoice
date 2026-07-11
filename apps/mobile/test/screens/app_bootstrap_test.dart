import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/ai_service.dart';
import 'package:mobile/model_manager.dart';
import 'package:mobile/screens/app_bootstrap.dart';
import 'package:privoice_models/privoice_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_ai_engine.dart';
import '../fakes/fake_meeting_repository.dart';
import '../fakes/fake_model_downloader.dart';

ModelManager _readyManager() => ModelManager(
      downloader: FakeModelDownloader(installed: {
        ModelCatalog.parakeetStt.id,
        ModelCatalog.llama1b.id,
      }),
    );

Widget _boot(ModelManager m) => MaterialApp(
      home: AppBootstrap(
        repository: FakeMeetingRepository(),
        ai: AiService(engine: FakeAiEngine()),
        themeMode: ValueNotifier(ThemeMode.system),
        modelManager: m,
      ),
    );

void main() {
  testWidgets('first launch shows onboarding', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_boot(_readyManager()));
    await tester.pumpAndSettle();

    expect(find.text('Capture every meeting'), findsOneWidget); // page 1 visible
    expect(find.text('Skip'), findsOneWidget); // onboarding chrome present
    expect(find.text('On-device'), findsNothing); // not in the app yet
  });

  testWidgets('completing onboarding reveals home and starts download',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final m = _readyManager();
    await tester.pumpWidget(_boot(m));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('On-device'), findsOneWidget); // HomeScreen app-bar badge
    expect(m.allReady, isTrue); // ensureDefaultSet ran against installed fakes
  });

  testWidgets('returning user goes straight to home', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    await tester.pumpWidget(_boot(_readyManager()));
    await tester.pumpAndSettle();

    expect(find.text('Skip'), findsNothing);
    expect(find.text('On-device'), findsOneWidget);
  });
}
