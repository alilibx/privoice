import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Deletes meeting audio files that no meeting row references.
///
/// The invariant is single: **an audio file no meeting references is garbage.**
/// Deleting a meeting cannot delete its file directly, because Home's Undo
/// re-inserts the meeting and needs the file to outlive the row — so file
/// lifetime is tied to whether anything still references the file, never to the
/// delete call.
///
/// One predicate, two scopes. Both [collect] and [collectOne] ask the same
/// question of a file — is its name one a meeting-audio writer produces, and is
/// that name unreferenced? — and they differ only in how many files they ask it
/// about. **Which scope is safe depends entirely on whether the moment is
/// quiescent:**
///
/// - [collect] sweeps the whole directory, so it is only safe when nothing can
///   be writing meeting audio. Meeting audio is legitimately unreferenced while
///   it is being captured: `AppAudioRecorder.start` creates `meeting_<ms>.wav`
///   immediately and `RecordScreen` inserts the row only after transcription
///   finishes — and `ImportScreen` does the same, minutes later for a long
///   file. A sweep during that window deletes the capture in progress. App
///   startup is the one genuinely quiescent moment (nothing can be capturing
///   before `runApp`), so startup owns the sweep.
/// - [collectOne] considers a single named file, so it is safe anywhere. Use it
///   from anywhere the app is live — notably `HomeScreen`, whose delete
///   continuation resumes when the Undo SnackBar closes and can therefore run
///   while a capture is in flight *or* while another delete's Undo window is
///   still open. `ScaffoldMessenger` sits above the `Navigator`, so pushing a
///   capture screen does not suspend that continuation.
///
/// If a whole-directory sweep is ever wanted at a non-quiescent moment (a
/// periodic sweep, a background task, a "reclaim space" button), make in-flight
/// files unmistakable — write to a `.part` name and rename on commit, or move
/// meeting audio into its own subdirectory — rather than weakening the
/// predicate.
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

  /// Sweeps [directory] and deletes every meeting audio file whose name is not
  /// among [referencedPaths]. Returns how many files were deleted.
  ///
  /// **Only safe at a quiescent moment** — see the class doc. Today that means
  /// app startup and nothing else; anywhere the app is live, use [collectOne].
  ///
  /// Matching is by file name, not by full path: `audioPath` is persisted
  /// absolute, and a stale directory prefix should still protect the file. The
  /// asymmetry is deliberate — the failure mode of name matching is keeping a
  /// file we could have deleted, never deleting one we needed.
  Future<int> collect(Iterable<String> referencedPaths) async {
    if (!await directory.exists()) return 0;

    final keep = _keepSet(referencedPaths);

    // Snapshot the listing BEFORE deleting anything: a file created after this
    // completes cannot be collected by this pass, which closes the race with a
    // capture that starts mid-sweep.
    final candidates = await directory
        .list(followLinks: false)
        .where((entity) => entity is File)
        .map((entity) => entity.path)
        .toList();

    var deleted = 0;
    for (final path in candidates) {
      if (await _collectFile(path, keep)) deleted++;
    }
    return deleted;
  }

  /// Deletes [path] if it is meeting audio in [directory] and no meeting still
  /// references it. Returns true if the file was deleted.
  ///
  /// **Safe at any moment**, because it can only ever touch the one file named,
  /// so a capture in flight (a different, newer name) and another pending
  /// delete's file (also a different name) are both untouchable by construction.
  /// This is what `HomeScreen` uses after its Undo window closes.
  ///
  /// Tolerant by design: `''` (the dev seed's `audioPath`), a name no writer
  /// produces, a path outside [directory], and a file that is already gone all
  /// return false rather than throwing.
  Future<bool> collectOne(
      String path, Iterable<String> referencedPaths) async {
    final name = p.basename(path);
    if (name.isEmpty) return false;
    // Resolved against [directory] rather than trusted as given, for the same
    // reason [collect] matches on names: a stale container prefix must not
    // point a delete at somewhere this store does not own.
    return _collectFile(p.join(directory.path, name), _keepSet(referencedPaths));
  }

  static Set<String> _keepSet(Iterable<String> referencedPaths) =>
      referencedPaths
          .where((path) => path.isNotEmpty)
          .map(p.basename)
          .toSet();

  /// The one predicate, in one place: a file is garbage iff its name is one a
  /// meeting-audio writer produces **and** no live row references that name.
  static bool _isGarbage(String name, Set<String> keep) =>
      isMeetingAudioFileName(name) && !keep.contains(name);

  /// Deletes [path] iff [_isGarbage]. Returns whether it was deleted.
  Future<bool> _collectFile(String path, Set<String> keep) async {
    if (!_isGarbage(p.basename(path), keep)) return false;
    try {
      await File(path).delete();
      return true;
    } on FileSystemException {
      // Missing, vanished between the check and the delete, or not ours to
      // remove. Leaving it is harmless — the next pass retries.
      return false;
    }
  }
}
