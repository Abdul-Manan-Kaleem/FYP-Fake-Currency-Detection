import 'dart:io';

import 'package:fake_currency_detector/features/verification/data/models/feature_check_model.dart';
import 'package:fake_currency_detector/features/verification/data/models/note_analysis_model.dart';
import 'package:fake_currency_detector/features/verification/data/on_device/image_preprocessor.dart';
import 'package:fake_currency_detector/features/verification/data/on_device/microprint_reader.dart';
import 'package:fake_currency_detector/features/verification/domain/verification_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  MicroprintModel eval(int expected, List<String> texts) =>
      MicroprintRules.evaluate(expected, texts, source: 'scan');

  group('counting the repeated border text', () {
    test('run-together microprint is counted', () {
      expect(eval(5000, ['500050005000500050005000']).occurrences, 6);
    });

    test('spaced and split across strips', () {
      expect(eval(1000, ['1000 1000', 'x 1000 ·', '1000']).occurrences, 4);
    });

    test('OCR look-alikes are corrected (O→0, I→1)', () {
      expect(eval(1000, ['1OOO I000 1000']).occurrences, 3);
    });

    test('Rs 500 microprint', () {
      expect(eval(500, ['500 500 500 500']).occurrences, 4);
    });

    test('a single corner numeral is not microprint', () {
      expect(eval(5000, ['5000']).occurrences, lessThan(3));
    });

    test('a different value clearly repeated is a conflict', () {
      final m = eval(5000, ['1000100010001000']);
      expect(m.occurrences, 0);
      expect(m.conflicting, 1000);
      expect(m.conflictingOccurrences, 4);
    });

    test('"500" inside "5000" is not a conflict on a Rs 5,000', () {
      final m = eval(5000, ['5000 5000 5000']);
      expect(m.conflicting, isNull);
    });

    test('no conflict is reported when the expected value is present', () {
      expect(eval(1000, ['1000 1000 1000 5000 5000 5000']).conflicting, isNull);
    });
  });

  group('engine check', () {
    final engine = VerificationEngine(clock: () => DateTime(2026, 10, 25));
    const q = ImageQualityModel(blurScore: 0.1, glareScore: 0.05, brightness: 0.5);

    NoteAnalysisModel note(int denom, {MicroprintModel? microprint}) =>
        NoteAnalysisModel(
          isBanknote: true,
          banknoteConfidence: 0.95,
          front: SideDetectionModel(
            quality: q,
            denomination: denom,
            denominationConfidence: 0.95,
            sbpSeals: const FeatureDetectionModel(count: 1, confidence: 0.9),
            securityThreads: const FeatureDetectionModel(count: 1, confidence: 0.9),
            securityLines: const FeatureDetectionModel(count: 0, confidence: 1),
            securityDots: const FeatureDetectionModel(count: 1, confidence: 0.9),
            printedYear:
                const PrintedYearModel(detected: true, value: '2022', confidence: 0.9),
            serialNumbers: const [
              SerialReadModel(text: 'AK4718263', confidence: 0.9),
              SerialReadModel(text: 'AK4718263', confidence: 0.9),
            ],
          ),
          back: SideDetectionModel(
            quality: q,
            denomination: denom,
            denominationConfidence: 0.95,
            sbpSeals: const FeatureDetectionModel(count: 3, confidence: 0.9),
          ),
          rs5000OnlyReason: 'Only for Rs 5,000 notes',
          microprint: microprint,
        );

    FeatureCheckModel check(NoteAnalysisModel a) => engine
        .evaluate(a)
        .checks
        .firstWhere((c) => c.id == FeatureCheckId.microprint);

    test('read 3+ times → pass', () {
      final c = check(note(5000, microprint: eval(5000, ['5000 5000 5000 5000'])));
      expect(c.status, CheckStatus.pass);
    });

    test('too small to read → not checked (never fake)', () {
      final a = note(5000, microprint: eval(5000, ['50']));
      expect(check(a).status, CheckStatus.skipped);
      expect(check(a).summary, contains('close-up'));
    });

    test('different denomination repeated → fail', () {
      final a = note(5000, microprint: eval(5000, ['1000100010001000']));
      expect(check(a).status, CheckStatus.fail);
    });

    // Rs 5,000 only for now: every other note has no microprint row at all.
    for (final denom in [10, 20, 50, 100, 500, 1000]) {
      test('Rs $denom → no microprint row', () {
        final r = engine.evaluate(note(denom));
        expect(r.checks.any((c) => c.id == FeatureCheckId.microprint), isFalse);
      });
    }

    test('close-up result replaces the scan result', () {
      final a = note(5000, microprint: eval(5000, ['50']))
          .withMicroprint(MicroprintRules.evaluate(
              5000, ['5000 5000 5000 5000'], source: 'close-up'));
      final c = check(a);
      expect(c.status, CheckStatus.pass);
      expect(c.summary, contains('close-up'));
    });
  });

  test('edge strips: four full-resolution bands, side bands turned flat', () {
    final dir = Directory.systemTemp.createTempSync('edge_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final paths = ImagePreprocessor.writeEdgeStrips(
        img.Image(width: 3000, height: 1300), dir.path, 't');
    expect(paths, hasLength(4));
    final top = img.decodeBmp(File(paths[0]).readAsBytesSync())!;
    final left = img.decodeBmp(File(paths[2]).readAsBytesSync())!;
    // Full resolution (not the 2048 working copy): 10% of 1300 = 130 px,
    // enlarged to 180 px tall keeping proportions.
    expect(top.height, 180);
    expect(top.width, greaterThanOrEqualTo(3000));
    expect(left.width, greaterThan(left.height)); // rotated to run horizontally
  });
}
