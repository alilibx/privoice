/// The source file could not be decoded — unsupported container, DRM, no
/// audio track, or corrupt data. [message] is user-facing.
class AudioImportException implements Exception {
  const AudioImportException(this.message);
  final String message;
  @override
  String toString() => 'AudioImportException: $message';
}

/// Converts an arbitrary audio or video file into the one format the on-device
/// STT pipeline accepts.
///
/// Behind an interface so the native decoder can be replaced without touching
/// callers, per the project rule that native bindings stay swappable.
abstract class AudioImporter {
  /// Decode [sourcePath] — any container the platform supports, including
  /// video, from which the audio track is extracted — and write 16 kHz mono
  /// 16-bit PCM WAV to [targetPath].
  ///
  /// [sourcePath] and [targetPath] must differ: a failed conversion cleans up
  /// by deleting [targetPath], and if the two paths were equal that would
  /// delete the caller's only copy of the source.
  ///
  /// Throws [AudioImportException] if the source cannot be decoded, or if
  /// [sourcePath] equals [targetPath].
  Future<void> toSttWav({
    required String sourcePath,
    required String targetPath,
  });
}
