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
      actionItems: ['do a', 'do b'],
    ));
    final loaded = await repo.byId(saved.id!);
    expect(loaded?.minutes, contains('Summary'));
    expect(loaded?.actionItems, ['do a', 'do b']);
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
    await repo.update(saved.copyWith(minutes: 'ok', actionItems: ['x']));
    expect((await repo.byId(saved.id!))?.actionItems, ['x']);
  });
}
