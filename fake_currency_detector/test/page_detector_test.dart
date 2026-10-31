import 'package:fake_currency_detector/features/verification/data/on_device/page_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? check(double aspect, double white, [double? coverage]) =>
      PageDetector.rejection(
        side: 'FRONT',
        aspectRatio: aspect,
        paperWhiteFraction: white,
        noteCoverage: coverage,
      );

  test('blank or printed A4 page is rejected as paper', () {
    expect(check(1.414, 0.82), contains('printer paper'));
    expect(check(1.414, 0.40), isNot(contains('A4')));
  });

  test('note printed on an A4 page (small note box) is rejected', () {
    expect(check(1.41, 0.12, 0.30), contains('printed on paper'));
  });

  test('US-letter page shape is also caught', () {
    expect(check(1.294, 0.70), isNotNull);
  });

  test('mostly white image of any shape is rejected', () {
    expect(check(1.8, 0.60), contains('blank white paper'));
  });

  test('a real note crop passes', () {
    expect(check(2.1, 0.03, 0.97), isNull);
    expect(check(1.8, 0.08, 0.95), isNull);
  });

  test('guidance tells the user what to do', () {
    expect(PageDetector.guidance.first, 'What to do:');
    expect(PageDetector.guidance.length, greaterThan(2));
  });
}
