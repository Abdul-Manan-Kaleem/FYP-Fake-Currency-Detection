import 'package:fake_currency_detector/features/verification/data/on_device/partial_note_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? check(double aspect, int denom, {double score = 0.9}) =>
      PartialNoteDetector.rejection(
        side: 'FRONT',
        aspectRatio: aspect,
        denomination: denom,
        noteScore: score,
      );

  const notes = [10, 20, 50, 100, 500, 1000, 5000];

  for (final d in notes) {
    final (len, h) = PartialNoteDetector.noteSizesMm[d]!;
    double ratio(double l, double hh) => l > hh ? l / hh : hh / l;

    group('Rs $d (${len}x$h mm)', () {
      test('whole note passes', () {
        expect(check(ratio(len.toDouble(), h.toDouble()), d), isNull);
      });

      test('whole note with a little background (+6% each way) passes', () {
        expect(check(ratio(len * 1.06 + 6, h * 1.06 + 6), d), isNull);
      });

      test('left or right half is rejected', () {
        expect(check(ratio(len / 2, h.toDouble()), d), contains('only part'));
      });

      test('three quarters is rejected', () {
        expect(check(ratio(len * 0.72, h.toDouble()), d), isNotNull);
      });

      test('top or bottom half is rejected', () {
        expect(check(ratio(len.toDouble(), h / 2), d), contains('top or bottom'));
      });
    });
  }

  test('uncertain denomination uses the generic note range', () {
    expect(check(2.2, 5000, score: 0.3), isNull);
    expect(check(1.2, 5000, score: 0.3), isNotNull);
  });

  test('guidance tells the user what to do', () {
    expect(PartialNoteDetector.guidance.first, 'What to do:');
  });
}
