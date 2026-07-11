import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/record_screen.dart';

import '../fakes/fake_audio_recorder.dart';
import '../fakes/fake_meeting_repository.dart';

void main() {
  testWidgets('idle shows the mic button and start caption', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RecordScreen(
        repository: FakeMeetingRepository(),
        recorder: FakeAudioRecorderHandle(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Tap to start recording'), findsOneWidget);
    expect(find.byKey(const Key('recordButton')), findsOneWidget);
  });

  testWidgets('permission denied shows an error message', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RecordScreen(
        repository: FakeMeetingRepository(),
        recorder: FakeAudioRecorderHandle(permission: false),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recordButton')));
    await tester.pumpAndSettle();
    expect(find.textContaining('permission'), findsOneWidget);
  });

  testWidgets('tapping start enters recording: timer, stop caption, waveform',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RecordScreen(
        repository: FakeMeetingRepository(),
        recorder: FakeAudioRecorderHandle(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recordButton')));
    await tester.pump(); // resolve _start futures → recording phase
    await tester.pump(); // drain the fake level stream

    expect(find.text('Tap to stop & transcribe'), findsOneWidget);
    expect(find.byKey(const Key('waveform')), findsOneWidget);

    // Dispose the screen so the periodic elapsed-ticker is cancelled (no
    // pending-timer failure at test end).
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
  });

  testWidgets('pressing back while recording asks to discard', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RecordScreen(
        repository: FakeMeetingRepository(),
        recorder: FakeAudioRecorderHandle(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recordButton')));
    await tester.pump(); // recording phase
    await tester.pump(); // drain levels

    // Back (via the close button) must be intercepted while recording.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(); // onPopInvoked → showDialog
    await tester.pump(const Duration(milliseconds: 350)); // dialog animates in
    expect(find.text('Discard recording?'), findsOneWidget);

    // Tear down (closes dialog + disposes the screen → cancels the ticker).
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(milliseconds: 350));
  });
}
