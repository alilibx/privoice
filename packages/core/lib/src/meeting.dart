/// Lifecycle of a recorded meeting through the pipeline.
enum MeetingStatus { recorded, transcribing, done, failed }

/// One recorded meeting: its audio, and (once processed) its transcript.
/// Minutes/summary land in a later slice.
class Meeting {
  const Meeting({
    this.id,
    required this.title,
    required this.createdAt,
    required this.audioPath,
    required this.durationMs,
    this.transcript,
    this.status = MeetingStatus.recorded,
  });

  final int? id;
  final String title;
  final DateTime createdAt;
  final String audioPath;
  final int durationMs;
  final String? transcript;
  final MeetingStatus status;

  Meeting copyWith({
    int? id,
    String? title,
    String? transcript,
    MeetingStatus? status,
  }) {
    return Meeting(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt,
      audioPath: audioPath,
      durationMs: durationMs,
      transcript: transcript ?? this.transcript,
      status: status ?? this.status,
    );
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'title': title,
        'created_at': createdAt.millisecondsSinceEpoch,
        'audio_path': audioPath,
        'duration_ms': durationMs,
        'transcript': transcript,
        'status': status.name,
      };

  factory Meeting.fromRow(Map<String, Object?> row) => Meeting(
        id: row['id'] as int?,
        title: row['title'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        audioPath: row['audio_path'] as String,
        durationMs: row['duration_ms'] as int,
        transcript: row['transcript'] as String?,
        status: MeetingStatus.values.byName(row['status'] as String),
      );
}
