import 'package:fake_currency_detector/features/verification/data/on_device/note_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<OcrLine> lines(List<String> t) => [for (final s in t) OcrLine(s, 0.9)];
  String read(List<String> t) => NoteTextParser.serialFromCrop(lines(t)).text;

  group('serialFromCrop', () {
    test('plain serial', () => expect(read(['ATG8159424']), 'ATG8159424'));

    test('spaces and punctuation', () {
      expect(read(['ATG 815-9424']), 'ATG8159424');
    });

    test('ML Kit splits letters and digits into two lines', () {
      expect(read(['ATG', '8159424']), 'ATG8159424');
    });

    test('progressive serial split into small and large digits', () {
      expect(read(['ATG815', '9424']), 'ATG8159424');
    });

    test('letter look-alikes inside the digits are corrected', () {
      expect(read(['ATG8I59O24']), 'ATG8159024');
      expect(read(['ATG8l5S424']), 'ATG8155424');
      expect(read(['ATGB159424']), 'ATG8159424');
    });

    test('digit look-alikes inside the prefix are corrected', () {
      expect(read(['A7G8159424']), 'ATG8159424');
      expect(read(['0K4718263']), 'OK4718263');
    });

    test('neighbouring note text in the crop is ignored', () {
      expect(read(['1000', 'ATG8159424']), 'ATG8159424');
      expect(read(['ATG8159424', 'RUPEES']), 'ATG8159424');
    });

    test('two-letter serials', () => expect(read(['AK 4718263']), 'AK4718263'));

    test('does not take 7 digits out of a longer number', () {
      expect(read(['12345678901']), '');
    });

    test('genuinely different serials stay different', () {
      expect(read(['GH3381902']) == read(['GH3381907']), isFalse);
    });

    test('nothing usable → empty with zero confidence', () {
      final r = NoteTextParser.serialFromCrop(lines(['A1']));
      expect(r.isEmpty, isTrue);
      expect(r.confidence, 0);
      expect(NoteTextParser.serialFromCrop(const []).isEmpty, isTrue);
    });
  });

  group('reconcile two OCR passes per region', () {
    SerialRead r(String t) => SerialRead(t, 0.9, raw: t);

    test('one pass misread, the other matches the second serial → match', () {
      final (a, b) = NoteTextParser.reconcile(
        [r('ATG8159424'), r('ATG8159421')],
        [r('ATG8159424'), r('ATG8159424')],
      );
      expect(a.text, b.text);
      expect(a.confidence, greaterThanOrEqualTo(0.5));
    });

    test('both regions stable but different → real mismatch, confident', () {
      final (a, b) = NoteTextParser.reconcile(
        [r('GH3381902'), r('GH3381902')],
        [r('GH3381907'), r('GH3381907')],
      );
      expect(a.text, 'GH3381902');
      expect(b.text, 'GH3381907');
      expect(a.confidence, greaterThanOrEqualTo(0.5));
      expect(b.confidence, greaterThanOrEqualTo(0.5));
    });

    test('passes disagree and nothing lines up → low confidence (unclear)', () {
      final (a, b) = NoteTextParser.reconcile(
        [r('ATG8159424'), r('ATG8159724')],
        [r('ATG8159421'), r('ATG8159429')],
      );
      expect(a.confidence, lessThan(0.5));
      expect(b.confidence, lessThan(0.5));
    });

    test('one pass empty still uses the other', () {
      final (a, b) = NoteTextParser.reconcile(
        [SerialRead.empty, r('ATG8159424')],
        [r('ATG8159424'), SerialRead.empty],
      );
      expect(a.text, 'ATG8159424');
      expect(b.text, 'ATG8159424');
    });
  });

  group('yearFromCrop', () {
    test('reads a plausible year', () {
      expect(NoteTextParser.yearFromCrop(lines(['2O22']), maxYear: 2026), '2022');
    });

    test('rejects future or impossible years', () {
      expect(NoteTextParser.yearFromCrop(lines(['2091']), maxYear: 2026), isNull);
    });
  });
}
