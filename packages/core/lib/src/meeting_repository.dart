import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'meeting.dart';

/// Storage contract for meetings. UI depends on this, not on sqflite.
abstract class MeetingRepository {
  Future<List<Meeting>> all();
  Future<Meeting?> byId(int id);
  Future<Meeting> insert(Meeting meeting);
  Future<void> update(Meeting meeting);
  Future<void> delete(int id);
}

/// sqflite-backed [MeetingRepository]. Kept behind the interface so the store
/// can be swapped (e.g. drift) without touching the UI.
class SqfliteMeetingRepository implements MeetingRepository {
  SqfliteMeetingRepository._(this._db);

  /// Wraps an already-open [Database] — used by tests (in-memory ffi).
  SqfliteMeetingRepository.fromDatabase(this._db);

  final Database _db;

  static const schemaVersion = 3;

  static Future<void> onCreate(Database db, int version) async {
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

  static Future<void> onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE meetings ADD COLUMN minutes TEXT');
      await db.execute('ALTER TABLE meetings ADD COLUMN action_items TEXT');
    }
    if (oldVersion < 3) {
      // action_items moved from newline-joined text to a JSON array of
      // {text, done}. Convert any legacy rows in place; leave JSON rows alone.
      final rows = await db.query('meetings', columns: ['id', 'action_items']);
      for (final row in rows) {
        final raw = row['action_items'] as String?;
        if (raw == null || raw.trim().isEmpty) continue;
        if (raw.trimLeft().startsWith('[')) continue; // already JSON
        final items = raw
            .split('\n')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => {'text': s, 'done': false})
            .toList();
        await db.update(
          'meetings',
          {'action_items': jsonEncode(items)},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
  }

  static Future<SqfliteMeetingRepository> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final db = await openDatabase(
      p.join(dir.path, 'privoice.db'),
      version: schemaVersion,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
    );
    return SqfliteMeetingRepository._(db);
  }

  @override
  Future<List<Meeting>> all() async {
    final rows = await _db.query('meetings', orderBy: 'created_at DESC');
    return rows.map(Meeting.fromRow).toList();
  }

  @override
  Future<Meeting?> byId(int id) async {
    final rows = await _db.query('meetings', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Meeting.fromRow(rows.first);
  }

  @override
  Future<Meeting> insert(Meeting meeting) async {
    final row = meeting.toRow()..remove('id');
    final id = await _db.insert('meetings', row);
    return meeting.copyWith(id: id);
  }

  @override
  Future<void> update(Meeting meeting) async {
    await _db.update('meetings', meeting.toRow(),
        where: 'id = ?', whereArgs: [meeting.id]);
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete('meetings', where: 'id = ?', whereArgs: [id]);
  }
}
