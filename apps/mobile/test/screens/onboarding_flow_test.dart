import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/onboarding_flow.dart';

void main() {
  testWidgets('advances through pages and Start fires onDone', (tester) async {
    var done = false;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingFlow(onDone: () => done = true),
    ));
    await tester.pumpAndSettle();

    // Page 1: welcome, Next visible, Start not yet.
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Start'), findsNothing);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Page 3: Start visible.
    expect(find.text('Start'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
  });

  testWidgets('Skip fires onDone immediately', (tester) async {
    var done = false;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingFlow(onDone: () => done = true),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
  });
}
