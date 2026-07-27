import 'dart:io';

import 'package:audio_decoder/audio_decoder.dart';

import 'audio_importer.dart';

/// [AudioImporter] backed by `audio_decoder`, which wraps the platform
/// decoders (AVFoundation on iOS, MediaCodec on Android) rather than bundling
/// FFmpeg — FFmpegKit was archived in June 2025.
class AudioDecoderImporter implements AudioImporter {
  const AudioDecoderImporter();

  /// The format `WavReader` and the STT models require. Kept here as the
  /// single place the conversion target is stated.
  static const int sampleRate = 16000;
  static const int channels = 1;
  static const int bitDepth = 16;

  @override
  Future<void> toSttWav({
    required String sourcePath,
    required String targetPath,
  }) async {
    if (sourcePath == targetPath) {
      // Guard against the failure-path cleanup below deleting the caller's
      // only copy of the source. This is a caller bug, not a bad user file,
      // so it is worded accordingly rather than blaming the file.
      throw const AudioImportException(
        'Import misconfigured: source and destination paths must differ.',
      );
    }
    if (!await File(sourcePath).exists()) {
      throw const AudioImportException('That file could no longer be found.');
    }
    try {
      await AudioDecoder.convertToWav(
        sourcePath,
        targetPath,
        sampleRate: sampleRate,
        channels: channels,
        bitDepth: bitDepth,
      );
    } catch (e) {
      // Delete a partial file so a retry starts clean and no half-WAV is left
      // behind for the reader to choke on.
      final partial = File(targetPath);
      if (await partial.exists()) {
        await partial.delete();
      }
      throw AudioImportException(
        "That file couldn't be read. It may be an unsupported format, "
        'protected, or damaged.',
      );
    }
    final out = File(targetPath);
    if (!await out.exists() || await out.length() == 0) {
      throw const AudioImportException(
        'That file has no audio track we can read.',
      );
    }
  }
}
