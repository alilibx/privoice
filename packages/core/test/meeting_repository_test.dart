import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_core/privoice_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<SqfliteMeetingRepository> _memoryRepo() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: SqfliteMeetingRepository.schemaVersion,
      onCreate: SqfliteMeetingRepository.onCreate,
      onUpgrade: SqfliteMeetingRepository.onUpgrade,
      singleInstance: false, // isolate each test's in-memory db
    ),
  );
  return SqfliteMeetingRepository.fromDatabase(db);
}

Meeting _m(String title, {DateTime? at}) => Meeting(
      title: title,
      createdAt: at ?? DateTime(2026, 7, 10, 10),
      audioPath: '/a.wav',
      durationMs: 1000,
      transcript: 't',
    );

void main() {
  setUpAll(sqfliteFfiInit);

  test('insert assigns an id and byId returns it', () async {
    final repo = await _memoryRepo();
    final saved = await repo.insert(_m('One'));
    expect(saved.id, isNotNull);
    expect((await repo.byId(saved.id!))?.title, 'One');
  });

  test('all() returns newest first', () async {
    final repo = await _memoryRepo();
    await repo.insert(_m('Older', at: DateTime(2026, 7, 10, 9)));
    await repo.insert(_m('Newer', at: DateTime(2026, 7, 10, 12)));
    final all = await repo.all();
    expect(all.map((m) => m.title).toList(), ['Newer', 'Older']);
  });

  test('update persists minutes and action items', () async {
    final repo = await _memoryRepo();
    final saved = await repo.insert(_m('M'));
    await repo.update(saved.copyWith(
      minutes: '### Summary\nx',
      actionItems: const [ActionItem(text: 'do a'), ActionItem(text: 'do b')],
    ));
    final loaded = await repo.byId(saved.id!);
    expect(loaded?.minutes, contains('Summary'));
    expect(loaded?.actionItems,
        const [ActionItem(text: 'do a'), ActionItem(text: 'do b')]);
  });

  test('delete removes the row', () async {
    final repo = await _memoryRepo();
    final saved = await repo.insert(_m('Gone'));
    await repo.delete(saved.id!);
    expect(await repo.byId(saved.id!), isNull);
    expect(await repo.all(), isEmpty);
  });

  test('v1 → v2 upgrade adds minutes/action_items columns', () async {
    // Open as v1 schema, then reopen at current version to trigger onUpgrade.
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onCreate: (db, v) async {
          await db.execute('''
            CREATE TABLE meetings (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL, created_at INTEGER NOT NULL,
              audio_path TEXT NOT NULL, duration_ms INTEGER NOT NULL,
              transcript TEXT, status TEXT NOT NULL)
          ''');
        },
      ),
    );
    await SqfliteMeetingRepository.onUpgrade(db, 1, 2);
    // Should now accept the new columns.
    final repo = SqfliteMeetingRepository.fromDatabase(db);
    final saved = await repo.insert(_m('Upg'));
    await repo.update(
        saved.copyWith(minutes: 'ok', actionItems: const [ActionItem(text: 'x')]));
    expect((await repo.byId(saved.id!))?.actionItems,
        const [ActionItem(text: 'x')]);
  });

  test('v2->v3 migrates legacy newline action_items to JSON items', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: SqfliteMeetingRepository.onCreate,
        singleInstance: false,
      ),
    );
    // Seed a legacy row exactly as a v2 build would have written it.
    await db.insert('meetings', {
      'title': 'Legacy',
      'created_at': 0,
      'audio_path': '/a.wav',
      'duration_ms': 0,
      'transcript': 't',
      'action_items': 'do a\ndo b',
      'status': 'done',
    });

    await SqfliteMeetingRepository.onUpgrade(db, 2, 3);

    final stored = (await db.query('meetings')).single['action_items'] as String;
    expect(stored.trimLeft().startsWith('['), isTrue); // now JSON

    final repo = SqfliteMeetingRepository.fromDatabase(db);
    final loaded = (await repo.all()).single;
    expect(loaded.actionItems,
        const [ActionItem(text: 'do a'), ActionItem(text: 'do b')]);
    expect(loaded.actionItems.every((a) => !a.done), isTrue);
  });

  test('v2->v3 leaves JSON action_items untouched', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: SqfliteMeetingRepository.onCreate,
        singleInstance: false,
      ),
    );
    await db.insert('meetings', {
      'title': 'New',
      'created_at': 0,
      'audio_path': '/a.wav',
      'duration_ms': 0,
      'transcript': 't',
      'action_items': '[{"text":"keep","done":true}]',
      'status': 'done',
    });

    await SqfliteMeetingRepository.onUpgrade(db, 2, 3);

    final repo = SqfliteMeetingRepository.fromDatabase(db);
    expect((await repo.all()).single.actionItems,
        const [ActionItem(text: 'keep', done: true)]);
  });
}
