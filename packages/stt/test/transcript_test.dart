import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_stt/privoice_stt.dart';

void main() {
  test('fromSegments joins text with spaces and keeps duration', () {
    final t = Transcript.fromSegments(
      const [
        TranscriptSegment(text: 'hello', startSec: 0.0, endSec: 1.0),
        TranscriptSegment(text: 'world', startSec: 1.0, endSec: 2.0),
      ],
      const Duration(seconds: 2),
    );
    expect(t.fullText, 'hello world');
    expect(t.segments.length, 2);
    expect(t.audioDuration, const Duration(seconds: 2));
  });

  test('fromSegments trims and drops empty segment text', () {
    final t = Transcript.fromSegments(
      const [
        TranscriptSegment(text: '  hi  ', startSec: 0.0, endSec: 1.0),
        TranscriptSegment(text: '', startSec: 1.0, endSec: 2.0),
        TranscriptSegment(text: 'there', startSec: 2.0, endSec: 3.0),
      ],
      const Duration(seconds: 3),
    );
    expect(t.fullText, 'hi there');
  });
}
