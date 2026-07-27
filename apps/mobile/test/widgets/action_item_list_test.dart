import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/action_item_list.dart';
import 'package:privoice_core/privoice_core.dart';

void main() {
  late List<ActionItem> items;
  late List<String> log;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ActionItemList(
          items: items,
          onToggle: (i, done) async => log.add('toggle:$i:$done'),
          onEditText: (i, text) async => log.add('edit:$i:$text'),
          onAdd: (text) async => log.add('add:$text'),
          onDelete: (i) async => log.add('delete:$i'),
          onReorder: (a, b) async => log.add('reorder:$a:$b'),
        ),
      ),
    ));
  }

  setUp(() {
    log = [];
    // A DONE item stored first, an undone item stored second. This is the
    // discriminating arrangement: stored order and a done-last sort produce
    // genuinely different renderings here (Carol first vs. Bob first), so a
    // reintroduced sort actually gets caught. (An earlier version of this
    // fixture stored Bob-undone first and Carol-done second, which happens
    // to match done-last order too, so it could never fail no matter what
    // the widget did — fixed per code review.)
    items = const [
      ActionItem(text: 'Carol: release notes', done: true),
      ActionItem(text: 'Bob: finish login'),
    ];
  });

  testWidgets('renders items in stored order, not done-last order',
      (tester) async {
    await pump(tester);
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    // Carol (done) is stored first; a done-last sort would push her after
    // Bob (undone) instead. Asserting she stays first is what actually
    // catches a reintroduced sort.
    expect(texts.indexOf('Carol: release notes'),
        lessThan(texts.indexOf('Bob: finish login')));
  });

  testWidgets('tapping the checkbox reports a toggle', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    // Carol (done) is index 0 in stored order; tapping her checkbox
    // unchecks her.
    expect(log, contains('toggle:0:false'));
  });

  testWidgets('editing an item reports the new text', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Bob: finish login'));
    await tester.pumpAndSettle();
    expect(find.text('Edit action item'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Bob: finish login by Thu');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // Bob is index 1 in stored order.
    expect(log, contains('edit:1:Bob: finish login by Thu'));
  });

  testWidgets('adding an item reports the text', (tester) async {
    await pump(tester);
    await tester.tap(find.text('+ Add item'));
    await tester.pumpAndSettle();
    expect(find.text('New action item'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Dave: book the room');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(log, contains('add:Dave: book the room'));
  });

  testWidgets('adding an empty item is ignored', (tester) async {
    await pump(tester);
    await tester.tap(find.text('+ Add item'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(log, isEmpty);
  });

  testWidgets('deleting an item reports its index', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Delete item').first);
    await tester.pumpAndSettle();
    // Carol is index 0 in stored order.
    expect(log, contains('delete:0'));
  });

  testWidgets('dragging an item reports a reorder', (tester) async {
    items = const [
      ActionItem(text: 'first'),
      ActionItem(text: 'second'),
      ActionItem(text: 'third'),
    ];
    await pump(tester);

    // Drag 'first' down past 'second'. `ReorderableListView.onReorderItem`
    // (unlike the deprecated `onReorder`) only fires when the drop actually
    // changes the item's final position — a drag that ends up back where it
    // started legitimately reports nothing. 130px reliably crosses fully
    // past the next row for this list's item height (verified empirically:
    // smaller offsets can land back on the origin slot).
    final handle = find.byIcon(Icons.drag_handle_rounded).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveBy(const Offset(0, 130));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(log.where((e) => e.startsWith('reorder:')), isNotEmpty);
  });
}
