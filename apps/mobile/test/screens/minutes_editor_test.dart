import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/minutes_editor_screen.dart';

/// Captures the value popped from [MinutesEditorScreen] so the *test body*
/// can inspect it after driving further interaction (e.g. tapping Save).
///
/// `Navigator.push` only resolves once the pushed route actually pops, which
/// happens well after `_open` itself returns (it just opens the screen and
/// settles). Assigning straight into a local inside `_open` and returning
/// that local is therefore always null by the time `_open` hands control
/// back — it only proves the push *started*, never what it resolved to. A
/// mutable holder that outlives `_open` lets the test read the real popped
/// value once the route has actually closed.
class _PushResult {
  String? value;
}

Future<_PushResult> _open(WidgetTester tester, String initial) async {
  final holder = _PushResult();
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () async {
          holder.value = await Navigator.of(context).push<String>(
            MaterialPageRoute(
              builder: (_) => MinutesEditorScreen(initialText: initial),
            ),
          );
        },
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return holder;
}

void main() {
  testWidgets('shows the raw Markdown for editing', (tester) async {
    await _open(tester, '### Summary\nOriginal text.');
    expect(find.text('Edit minutes'), findsOneWidget);
    expect(find.text('### Summary\nOriginal text.'), findsOneWidget);
  });

  testWidgets('Save pops the edited text', (tester) async {
    final holder = await _open(tester, 'before');
    await tester.enterText(find.byType(TextField), 'after');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // The route is gone and the edited text came back.
    expect(find.byType(MinutesEditorScreen), findsNothing);
    expect(holder.value, 'after');
  });

  testWidgets('Cancel with no changes pops immediately without a dialog',
      (tester) async {
    final holder = await _open(tester, 'before');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(MinutesEditorScreen), findsNothing);
    // Distinguishes this path from Save: Cancel must yield null, never text.
    expect(holder.value, isNull);
  });

  testWidgets('Cancel with unsaved changes confirms first', (tester) async {
    final holder = await _open(tester, 'before');
    await tester.enterText(find.byType(TextField), 'edited');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    // Still editing, text preserved.
    expect(find.byType(MinutesEditorScreen), findsOneWidget);
    expect(find.text('edited'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(MinutesEditorScreen), findsNothing);
    expect(holder.value, isNull);
  });
}
