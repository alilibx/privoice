import 'package:flutter_test/flutter_test.dart';
import 'package:privoice_ai/privoice_ai.dart';

void main() {
  test('strips surrounding quotes and trailing punctuation', () {
    expect(cleanTitle('"Beta Launch Planning."'), 'Beta Launch Planning');
  });

  test('takes only the first line', () {
    expect(cleanTitle('Q3 Roadmap Review\nHere are the notes'),
        'Q3 Roadmap Review');
  });

  test('drops a leading "Title:" label', () {
    expect(cleanTitle('Title: Hiring Sync'), 'Hiring Sync');
  });

  test('caps to maxWords', () {
    expect(cleanTitle('one two three four five', maxWords: 3), 'one two three');
  });

  test('blank stays blank', () {
    expect(cleanTitle('   '), '');
  });

  test('strips trailing exclamation and other punctuation', () {
    expect(cleanTitle('Q3 Planning!'), 'Q3 Planning');
    expect(cleanTitle('Hiring Sync?'), 'Hiring Sync');
    expect(cleanTitle('Beta Launch,'), 'Beta Launch');
  });
}
