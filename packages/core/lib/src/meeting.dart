import 'dart:convert';

import 'action_item.dart';

/// Lifecycle of a recorded meeting through the pipeline.
enum MeetingStatus { recorded, transcribing, done, failed }

/// One recorded meeting: its audio, transcript, and AI outputs (minutes +
/// action items) once generated.
class Meeting {
  const Meeting({
    this.id,
    required this.title,
    required this.createdAt,
    required this.audioPath,
    required this.durationMs,
    this.transcript,
    this.minutes,
    this.actionItems = const [],
    this.status = MeetingStatus.recorded,
  });

  final int? id;
  final String title;
  final DateTime createdAt;
  final String audioPath;
  final int durationMs;
  final String? transcript;
  final String? minutes;
  final List<ActionItem> actionItems;
  final MeetingStatus status;

  Meeting copyWith({
    int? id,
    String? title,
    String? transcript,
    String? minutes,
    List<ActionItem>? actionItems,
    MeetingStatus? status,
  }) {
    return Meeting(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt,
      audioPath: audioPath,
      durationMs: durationMs,
      transcript: transcript ?? this.transcript,
      minutes: minutes ?? this.minutes,
      actionItems: actionItems ?? this.actionItems,
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
        'minutes': minutes,
        'action_items': actionItems.isEmpty
            ? null
            : jsonEncode(actionItems.map((a) => a.toJson()).toList()),
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
        minutes: row['minutes'] as String?,
        actionItems: _decodeActionItems(row['action_items'] as String?),
        status: MeetingStatus.values.byName(row['status'] as String),
      );

  static List<ActionItem> _decodeActionItems(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    // New format: a JSON array of {text, done}.
    if (raw.trimLeft().startsWith('[')) {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ActionItem.fromJson((e as Map).cast<String, Object?>()))
          .toList();
    }
    // Legacy format: newline-joined strings (pre-v3 rows).
    return raw
        .split('\n')
        .where((s) => s.trim().isNotEmpty)
        .map((s) => ActionItem(text: s))
        .toList();
  }
}
