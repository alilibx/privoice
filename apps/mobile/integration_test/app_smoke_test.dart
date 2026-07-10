import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/main.dart' as app;

/// Device-matrix smoke test (Firebase Test Lab friendly — no model needed).
/// Proves the app boots and the core UI works on real hardware / OS versions.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app launches to Home and opens the Record screen',
      (tester) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Home renders with the privacy badge.
    expect(find.text('Privoice'), findsOneWidget);
    expect(find.text('On-device'), findsOneWidget);
    expect(find.text('Record'), findsOneWidget);

    // Navigation into the Record screen works.
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    expect(find.text('New recording'), findsOneWidget);

    // Back to Home.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Privoice'), findsOneWidget);
  });
}
