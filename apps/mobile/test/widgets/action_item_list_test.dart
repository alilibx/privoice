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
    items = const [
      ActionItem(text: 'Bob: finish login'),
      ActionItem(text: 'Carol: release notes', done: true),
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
    // 'Bob' before 'Carol' is stored order; the old widget sank done items.
    expect(texts.indexOf('Bob: finish login'),
        lessThan(texts.indexOf('Carol: release notes')));
  });

  testWidgets('tapping the checkbox reports a toggle', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(log, contains('toggle:0:true'));
  });

  testWidgets('editing an item reports the new text', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Bob: finish login'));
    await tester.pumpAndSettle();
    expect(find.text('Edit action item'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Bob: finish login by Thu');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(log, contains('edit:0:Bob: finish login by Thu'));
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
    expect(log, contains('delete:0'));
  });
}
