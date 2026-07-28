import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:privoice_core/privoice_core.dart';

void main() {
  late Directory dir;
  late MeetingAudioStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('meeting_audio_store');
    store = MeetingAudioStore(dir);
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  File touch(String name) =>
      File(p.join(dir.path, name))..writeAsStringSync('x');

  test('deletes unreferenced recording and imported audio', () async {
    final recording = touch('meeting_1000.wav');
    final imported = touch('imported_2000.wav');

    expect(await store.collect(const []), 2);
    expect(recording.existsSync(), isFalse);
    expect(imported.existsSync(), isFalse);
  });

  test('keeps referenced audio and collects only the rest', () async {
    final kept = touch('meeting_1000.wav');
    final orphan = touch('meeting_2000.wav');

    expect(await store.collect([kept.path]), 1);
    expect(kept.existsSync(), isTrue);
    expect(orphan.existsSync(), isFalse);
  });

  test('never deletes the database or any other non-audio file', () async {
    // privoice.db lives in this very directory and no meeting references it.
    // A broader rule than the filename pattern would destroy the user's data.
    final files = [
      touch('privoice.db'),
      touch('privoice.db-wal'),
      touch('privoice.db-journal'),
      touch('notes.txt'),
      touch('meeting_abc.wav'), // no digits
      touch('my_meeting_1.wav'), // wrong prefix
      touch('meeting_1.mp3'), // wrong extension
    ];

    expect(await store.collect(const []), 0);
    for (final f in files) {
      expect(f.existsSync(), isTrue,
          reason: '${p.basename(f.path)} must never be collected');
    }
  });

  test('tolerates an empty audioPath among the referenced paths', () async {
    // The dev seed inserts a Meeting with audioPath: ''.
    final orphan = touch('meeting_1000.wav');
    expect(await store.collect(const ['']), 1);
    expect(orphan.existsSync(), isFalse);
  });

  test('tolerates a referenced path whose file is already gone', () async {
    final kept = touch('meeting_1000.wav');
    final missing = p.join(dir.path, 'meeting_9999.wav');

    expect(await store.collect([kept.path, missing]), 0);
    expect(kept.existsSync(), isTrue);
  });

  test('returns zero when the directory does not exist', () async {
    await dir.delete(recursive: true);
    expect(await store.collect(const []), 0);
  });

  test('protects a referenced file even if its stored path is stale', () async {
    // audioPath is persisted absolute, but a container path can differ from the
    // one recorded at write time. Matching on the file name means a stale
    // directory prefix still protects the file: the safe direction is to keep.
    final kept = touch('meeting_1000.wav');
    expect(await store.collect(const ['/old/container/meeting_1000.wav']), 0);
    expect(kept.existsSync(), isTrue);
  });

  test('isMeetingAudioFileName recognises exactly the writers we have', () {
    expect(MeetingAudioStore.isMeetingAudioFileName('meeting_1.wav'), isTrue);
    expect(MeetingAudioStore.isMeetingAudioFileName('imported_1.wav'), isTrue);
    expect(MeetingAudioStore.isMeetingAudioFileName('privoice.db'), isFalse);
    expect(MeetingAudioStore.isMeetingAudioFileName('meeting_.wav'), isFalse);
    expect(MeetingAudioStore.isMeetingAudioFileName('xmeeting_1.wav'), isFalse);
  });

  group('collectOne (the scope that is safe while the app is live)', () {
    test('deletes the named file when nothing references it', () async {
      final orphan = touch('meeting_1000.wav');
      expect(await store.collectOne(orphan.path, const []), isTrue);
      expect(orphan.existsSync(), isFalse);
    });

    test('keeps the named file when a row still references it', () async {
      // This is the Undo case: the row is back, so the file must stay.
      final kept = touch('meeting_1000.wav');
      expect(await store.collectOne(kept.path, [kept.path]), isFalse);
      expect(kept.existsSync(), isTrue);
    });

    test('never touches any file other than the one named', () async {
      // The whole point of the targeted scope: an in-flight capture and another
      // pending delete's audio are both unreferenced, and both must survive.
      final target = touch('meeting_1000.wav');
      final inFlightCapture = touch('meeting_9000.wav');
      final otherPendingDelete = touch('meeting_2000.wav');
      final db = touch('privoice.db');

      expect(await store.collectOne(target.path, const []), isTrue);
      expect(target.existsSync(), isFalse);
      expect(inFlightCapture.existsSync(), isTrue);
      expect(otherPendingDelete.existsSync(), isTrue);
      expect(db.existsSync(), isTrue);
    });

    test('tolerates an empty path', () async {
      final untouched = touch('meeting_1000.wav');
      expect(await store.collectOne('', const []), isFalse);
      expect(untouched.existsSync(), isTrue);
    });

    test('tolerates a name no writer produces', () async {
      final db = touch('privoice.db');
      expect(await store.collectOne(db.path, const []), isFalse);
      expect(db.existsSync(), isTrue);
    });

    test('tolerates a missing file', () async {
      final missing = p.join(dir.path, 'meeting_9999.wav');
      expect(await store.collectOne(missing, const []), isFalse);
    });

    test('a path outside the directory resolves inside it, never outside',
        () async {
      // A stale container prefix must not aim a delete somewhere this store
      // does not own; the name is resolved against [directory].
      final outside = await Directory.systemTemp.createTemp('outside_store');
      addTearDown(() async {
        if (outside.existsSync()) await outside.delete(recursive: true);
      });
      final stranger = File(p.join(outside.path, 'meeting_1000.wav'))
        ..writeAsStringSync('x');
      final ours = touch('meeting_1000.wav');

      expect(await store.collectOne(stranger.path, const []), isTrue);
      expect(stranger.existsSync(), isTrue,
          reason: 'a file outside the store directory is not ours to delete');
      expect(ours.existsSync(), isFalse);
    });
  });

  // Why MeetingRepository.delete is deliberately NOT changed to delete the file:
  // Home's Undo re-inserts the meeting, so the file must outlive the row. Making
  // delete() remove the file is the obvious fix and it breaks Undo — restoring a
  // meeting whose audio is already gone. Collection is therefore keyed on "is
  // anything still referencing this file", never on the delete call. If you are
  // here because you were about to move deletion into the repository: don't.
}
