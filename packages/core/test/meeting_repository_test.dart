import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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

// A real v2 schema: post minutes/action_items columns (added in v1->v2),
// pre minutes_edited_at (added in v3->v4). Used by tests that need to
// simulate a genuinely old database rather than today's full schema.
Future<void> _createV2Schema(Database db, int version) async {
  await db.execute('''
    CREATE TABLE meetings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      audio_path TEXT NOT NULL,
      duration_ms INTEGER NOT NULL,
      transcript TEXT,
      minutes TEXT,
      action_items TEXT,
      status TEXT NOT NULL
    )
  ''');
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
        // A real v2 schema (post minutes/action_items, pre minutes_edited_at).
        // Delegating to SqfliteMeetingRepository.onCreate would build today's
        // full schema instead, which already has minutes_edited_at and would
        // make the manual onUpgrade(db, 2, 3) call below re-add it and fail.
        onCreate: _createV2Schema,
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
        onCreate: _createV2Schema,
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

  test('v3 -> v4 migration adds minutes_edited_at and preserves rows',
      () async {
    // In-memory databases are destroyed on close, so a close+reopen against
    // inMemoryDatabasePath would silently hand back a fresh empty database
    // and onUpgrade would never really be exercised. Use a temp file so the
    // reopen hits the same database and sqflite's version machinery runs
    // onUpgrade for real.
    final dir = Directory.systemTemp.createTempSync('privoice_migration');
    final path = p.join(dir.path, 'v3.db');
    try {
      // Build a v3 database by hand: the pre-v4 schema, with a row in it.
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE meetings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                audio_path TEXT NOT NULL,
                duration_ms INTEGER NOT NULL,
                transcript TEXT,
                minutes TEXT,
                action_items TEXT,
                status TEXT NOT NULL
              )
            ''');
            await db.insert('meetings', {
              'title': 'Legacy meeting',
              'created_at': DateTime(2026, 7, 1).millisecondsSinceEpoch,
              'audio_path': '/tmp/legacy.wav',
              'duration_ms': 120000,
              'transcript': 'legacy transcript',
              'minutes': '### Summary\nLegacy.',
              'action_items': '[{"text":"do it","done":true}]',
              'status': 'done',
            });
          },
        ),
      );
      await db.close();

      // Reopen the same file at the current version so onUpgrade runs.
      final upgraded = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: SqfliteMeetingRepository.schemaVersion,
          onCreate: SqfliteMeetingRepository.onCreate,
          onUpgrade: SqfliteMeetingRepository.onUpgrade,
          singleInstance: false,
        ),
      );
      final repo = SqfliteMeetingRepository.fromDatabase(upgraded);
      final all = await repo.all();

      expect(all, hasLength(1));
      expect(all.first.title, 'Legacy meeting');
      expect(all.first.minutes, '### Summary\nLegacy.');
      expect(all.first.actionItems.single.text, 'do it');
      expect(all.first.actionItems.single.done, isTrue);
      // The new column exists and is null for pre-v4 rows. Check the raw row
      // for the key itself (not just via Meeting.fromRow, which treats an
      // absent column the same as a present-but-null one) so this actually
      // fails if the ALTER never ran, instead of vacuously passing.
      final rawRows = await upgraded.query('meetings');
      expect(rawRows.single.containsKey('minutes_edited_at'), isTrue,
          reason: 'minutes_edited_at column should exist after the v3->v4 '
              'migration');
      expect(all.first.minutesEditedAt, isNull);

      // The column must also be writable post-migration, not just present —
      // this is what later tasks (hand-editing minutes) rely on.
      final stamp = DateTime(2026, 7, 27, 12);
      final withStamp = await repo.insert(Meeting(
        title: 'New after migration',
        createdAt: DateTime(2026, 7, 27),
        audioPath: '/tmp/new.wav',
        durationMs: 1000,
        minutesEditedAt: stamp,
      ));
      expect((await repo.byId(withStamp.id!))?.minutesEditedAt, stamp);

      await upgraded.close();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
