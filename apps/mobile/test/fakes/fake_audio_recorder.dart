import 'dart:async';

import 'package:privoice_audio/privoice_audio.dart';

/// Test double for [AudioRecorderHandle] — no real mic.
class FakeAudioRecorderHandle implements AudioRecorderHandle {
  FakeAudioRecorderHandle({
    this.permission = true,
    this.levelValues = const [0.3, 0.7, 0.5],
  });

  final bool permission;
  final List<double> levelValues;
  bool started = false;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<String> stop() async => '/tmp/fake_meeting.wav';

  @override
  Future<void> dispose() async {}

  @override
  Stream<double> levels({Duration interval = const Duration(milliseconds: 150)}) =>
      Stream<double>.fromIterable(levelValues); // completes; no pending timer
}
