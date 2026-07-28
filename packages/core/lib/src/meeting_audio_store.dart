import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Deletes meeting audio files that no meeting row references.
///
/// The invariant is single: **an audio file no meeting references is garbage.**
/// Deleting a meeting cannot delete its file directly, because Home's Undo
/// re-inserts the meeting and needs the file to outlive the row — so file
/// lifetime is tied to whether anything still references the file, never to the
/// delete call. Prompt reclamation (after the Undo window closes) and the
/// startup backstop are both call sites of [collect].
///
/// **Precondition: only call [collect] when no recording or import is in
/// flight.** `ImportScreen` writes its WAV and inserts the `Meeting` row only
/// after transcription finishes — minutes later for a long file — so an
/// in-progress import is legitimately unreferenced and would be collected. That
/// is safe today only because both capture screens are pushed above Home in the
/// navigator, and the startup pass runs before any capture is possible. If that
/// ever stops holding (a periodic sweep, a background task, a "reclaim space"
/// button), make in-flight files unmistakable — write to a `.part` name and
/// rename on commit, or move meeting audio into its own subdirectory — rather
/// than weakening the sweep.
class MeetingAudioStore {
  const MeetingAudioStore(this.directory);

  /// The directory recordings and imports are actually written to:
  /// `AppAudioRecorder.start` and `ImportScreen._run` both use app documents.
  static Future<MeetingAudioStore> forApp() async =>
      MeetingAudioStore(await getApplicationDocumentsDirectory());

  final Directory directory;

  /// Names that meeting-audio writers produce. **Must stay in sync with every
  /// writer:** `RecordingConfig.fileName` (`meeting_<ms>.wav`) and
  /// `ImportScreen._run` (`imported_<ms>.wav`). A new naming scheme that is not
  /// added here leaks silently.
  ///
  /// This pattern is also the safety boundary: `privoice.db` and its journal
  /// siblings live in the same directory and are referenced by no meeting, so a
  /// broader rule than this would delete the user's database.
  static final RegExp _audioFileName = RegExp(r'^(meeting|imported)_\d+\.wav$');

  static bool isMeetingAudioFileName(String name) =>
      _audioFileName.hasMatch(name);

  /// Deletes meeting audio in [directory] whose file name is not among
  /// [referencedPaths]. Returns how many files were deleted.
  ///
  /// Matching is by file name, not by full path: `audioPath` is persisted
  /// absolute, and a stale directory prefix should still protect the file. The
  /// asymmetry is deliberate — the failure mode of name matching is keeping a
  /// file we could have deleted, never deleting one we needed.
  Future<int> collect(Iterable<String> referencedPaths) async {
    if (!await directory.exists()) return 0;

    final keep = referencedPaths
        .where((path) => path.isNotEmpty)
        .map(p.basename)
        .toSet();

    // Snapshot the listing BEFORE deleting anything: a file created after this
    // completes cannot be collected by this pass, which closes the race with a
    // capture that starts mid-sweep.
    final candidates = await directory
        .list(followLinks: false)
        .where((entity) => entity is File)
        .map((entity) => entity.path)
        .where((path) => isMeetingAudioFileName(p.basename(path)))
        .toList();

    var deleted = 0;
    for (final path in candidates) {
      if (keep.contains(p.basename(path))) continue;
      try {
        await File(path).delete();
        deleted++;
      } on FileSystemException {
        // Vanished between the snapshot and the delete, or not ours to remove.
        // Leaving it is harmless — the next collect retries.
      }
    }
    return deleted;
  }
}
