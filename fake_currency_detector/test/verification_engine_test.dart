import 'package:fake_currency_detector/features/verification/data/models/feature_check_model.dart';
import 'package:fake_currency_detector/features/verification/data/models/note_analysis_model.dart';
import 'package:fake_currency_detector/features/verification/data/models/verification_result_model.dart';
import 'fixtures/sample_analyses.dart';
import 'package:fake_currency_detector/features/verification/domain/verification_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final engine = VerificationEngine(clock: () => DateTime(2026, 10, 8));

  VerificationResultModel run(SampleAnalysis s) =>
      engine.evaluate(NoteAnalysisModel.fromJson(s.analysis.toJson()));

  group('sample detector outputs score as expected', () {
    test('clean Rs 5000 → PASSED APP CHECKS at 96%', () {
      final r = run(SampleAnalysis.authentic5000);
      expect(r.verdict, VerificationVerdict.real);
      expect(r.confidence.percentage, 96);
      expect(r.denomination, 5000);
      // The sample predates the genuine/counterfeit CNN, which shows as
      // skipped; every check that ran passed.
      expect(
        r.checks.where((c) => c.status != CheckStatus.skipped).every((c) => c.passed),
        isTrue,
      );
    });

    test('mismatched serials → SUSPICIOUS at 32%', () {
      final r = run(SampleAnalysis.mismatchedSerials);
      expect(r.verdict, VerificationVerdict.suspicious);
      expect(r.confidence.percentage, 32);
      final serial =
          r.checks.firstWhere((c) => c.id == FeatureCheckId.serialNumber);
      expect(serial.failed, isTrue);
      expect(serial.serialComparison!.mismatchCount, 2);
    });

    test('missing back seals → suspicious at 58%', () {
      final r = run(SampleAnalysis.missingBackSeals);
      expect(r.verdict, VerificationVerdict.suspicious);
      expect(r.confidence.percentage, 58);
    });

    test('blurry → unable to verify at 0%', () {
      final r = run(SampleAnalysis.blurry);
      expect(r.verdict, VerificationVerdict.unableToVerify);
      expect(r.confidence.percentage, 0);
    });

    test('not a banknote → rejection', () {
      final r = run(SampleAnalysis.notBanknote);
      expect(r.verdict, VerificationVerdict.notBanknote);
      expect(r.isBanknote, isFalse);
    });
  });

  group('rules', () {
    SideDetectionModel front({
      int denom = 100,
      int lines = 3,
      int dots = 0,
      int threads = 1,
      int seals = 1,
      List<String> serials = const ['AB1234567', 'AB1234567'],
      double serialConf = 0.95,
      String? year = '2020',
    }) =>
        SideDetectionModel(
          quality: const ImageQualityModel(
              blurScore: 0.1, glareScore: 0.1, brightness: 0.5),
          denomination: denom,
          denominationConfidence: 0.95,
          sbpSeals: FeatureDetectionModel(count: seals, confidence: 0.95),
          securityThreads: FeatureDetectionModel(count: threads, confidence: 0.95),
          securityLines: FeatureDetectionModel(count: lines, confidence: 0.95),
          securityDots: FeatureDetectionModel(count: dots, confidence: 0.95),
          printedYear: year == null
              ? null
              : PrintedYearModel(detected: true, value: year, confidence: 0.95),
          serialNumbers: [
            for (final s in serials)
              SerialReadModel(text: s, confidence: serialConf),
          ],
        );

    SideDetectionModel back({int denom = 100, int seals = 3}) =>
        SideDetectionModel(
          quality: const ImageQualityModel(
              blurScore: 0.1, glareScore: 0.1, brightness: 0.5),
          denomination: denom,
          denominationConfidence: 0.95,
          sbpSeals: FeatureDetectionModel(count: seals, confidence: 0.95),
        );

    VerificationResultModel eval(SideDetectionModel f, SideDetectionModel b,
            {double anomaly = 0.05}) =>
        engine.evaluate(NoteAnalysisModel(
          isBanknote: true,
          banknoteConfidence: 0.99,
          front: f,
          back: b,
          anomaly: AnomalyModel(anomalyScore: anomaly),
        ));

    test('all-pass note is always ≥ 85%', () {
      final r = eval(front(), back());
      expect(r.verdict, VerificationVerdict.real);
      expect(r.confidence.percentage, greaterThanOrEqualTo(85));
    });

    test('denomination mismatch drops below 40%', () {
      final r = eval(front(), back(denom: 50));
      expect(r.verdict, VerificationVerdict.suspicious);
      expect(r.confidence.percentage, lessThan(40));
    });

    for (final (a, b) in [
      ('12345678', '1234567'),
      ('12345678', '12345679'),
      ('12345678', '123456789'),
    ]) {
      test('serial $a vs $b fails', () {
        final r = eval(front(serials: [a, b]), back());
        expect(r.confidence.percentage, lessThan(40));
      });
    }

    // YOLO boxes a whole group of marks as one region, so region count is
    // 1..marks; only the mark TYPE and absurd region counts can fail.
    test('one grouped line region on Rs 100 passes', () {
      expect(eval(front(lines: 1), back()).verdict, VerificationVerdict.real);
    });

    test('more line regions than lines is suspicious', () {
      final r = eval(front(lines: 4), back());
      expect(r.verdict, isNot(VerificationVerdict.real));
      expect(r.confidence.percentage, lessThanOrEqualTo(84));
    });

    test('dots on a lines note (Rs 100) is suspicious', () {
      final r = eval(front(lines: 1, dots: 1), back());
      expect(r.verdict, VerificationVerdict.suspicious);
    });

    test('no line region on Rs 100 is suspicious', () {
      final r = eval(front(lines: 0), back());
      expect(r.verdict, VerificationVerdict.suspicious);
    });

    // Screenshot case: Rs 1,000 with both dots inside ONE dots box.
    test('Rs 1000 with a single dots region passes the mark check', () {
      final r = eval(
        front(denom: 1000, lines: 0, dots: 1),
        back(denom: 1000),
      );
      final mark = r.checks.firstWhere((c) => c.id == FeatureCheckId.linesDots);
      expect(mark.status, CheckStatus.pass);
    });

    // Rs 10, 20 and 50 have no security thread.
    for (final (denom, lines) in [(10, 0), (20, 1), (50, 1)]) {
      test('Rs $denom: thread is not applicable', () {
        final r = eval(
          front(denom: denom, lines: lines, threads: 0),
          back(denom: denom),
        );
        final t = r.checks
            .firstWhere((c) => c.id == FeatureCheckId.securityThread);
        expect(t.status, CheckStatus.notApplicable);
        expect(r.verdict, VerificationVerdict.real);
      });
    }

    test('Rs 50 uses lines, not dots', () {
      final r = eval(front(denom: 50, lines: 0, dots: 1, threads: 0),
          back(denom: 50));
      expect(r.verdict, VerificationVerdict.suspicious);
    });

    test('Rs 1000 with no thread at all is suspicious', () {
      final r = eval(front(denom: 1000, lines: 0, dots: 1, threads: 0),
          back(denom: 1000));
      expect(r.verdict, VerificationVerdict.suspicious);
    });

    test('two threads fail', () {
      final r = eval(front(threads: 2), back());
      expect(r.checks
          .firstWhere((c) => c.id == FeatureCheckId.securityThread)
          .failed, isTrue);
    });

    test('dots expected for Rs 1000', () {
      final r = eval(front(denom: 1000, lines: 0, dots: 2), back(denom: 1000));
      expect(r.verdict, VerificationVerdict.real);
    });

    test('OCR failure → unable to verify, not fake', () {
      final r = eval(front(serialConf: 0.2), back());
      expect(r.verdict, VerificationVerdict.unableToVerify);
    });

    test('missing printed year fails', () {
      final r = eval(front(year: null), back());
      expect(r.verdict, isNot(VerificationVerdict.real));
    });

    test('strong MobileNetV3 anomaly → suspicious', () {
      final r = eval(front(), back(), anomaly: 0.8);
      expect(r.verdict, isNot(VerificationVerdict.real));
    });

    test('single side → INCOMPLETE', () {
      expect(engine.incomplete(hasFront: true).verdict,
          VerificationVerdict.incomplete);
    });

    test('result JSON round-trips', () {
      final r = run(SampleAnalysis.authentic5000);
      final back = VerificationResultModel.fromJson(r.toJson());
      expect(back.confidence.percentage, r.confidence.percentage);
      expect(back.checks.length, r.checks.length);
    });
  });

  group('analysis without YOLO feature counts', () {
    const sharp = ImageQualityModel(
        blurScore: 0.1, glareScore: 0.05, brightness: 0.5);

    NoteAnalysisModel analysis({
      List<String> serials = const ['AK4718263', 'AK4718263'],
      double altered = 0.1,
      int backDenom = 5000,
      String? year = '2022',
    }) =>
        NoteAnalysisModel(
          isBanknote: true,
          banknoteConfidence: 1,
          front: SideDetectionModel(
            quality: sharp,
            denomination: 5000,
            denominationConfidence: 0.85,
            printedYear: PrintedYearModel(
                detected: true, value: year, confidence: year == null ? 0 : 0.9),
            serialNumbers: [
              for (final s in serials)
                SerialReadModel(text: s, confidence: s.isEmpty ? 0 : 0.9),
            ],
          ),
          back: SideDetectionModel(
            quality: sharp,
            denomination: backDenom,
            denominationConfidence: 0.85,
          ),
          anomaly: AnomalyModel(
              anomalyScore: altered, frontScore: altered, backScore: altered),
          counterfeitCnn: const CounterfeitCnnModel(
              frontCounterfeit: 0.1, backCounterfeit: 0.1),
        );

    test('YOLO-only checks are skipped, not passed', () {
      final r = engine.evaluate(analysis());
      final skipped = r.checks
          .where((c) => c.status == CheckStatus.skipped)
          .map((c) => c.id)
          .toSet();
      expect(skipped, {
        FeatureCheckId.sbpSeals,
        FeatureCheckId.linesDots,
        FeatureCheckId.securityThread,
        FeatureCheckId.microprint, // sample has no border OCR
        FeatureCheckId.monument, // sample has no monument result
      });
      expect(r.verdict, VerificationVerdict.real);
      expect(r.messages.any((m) => m.startsWith('Not checked')), isTrue);
    });

    test('Rs 5000 CNN altered probability above 0.5 is not PASSED', () {
      final r = engine.evaluate(analysis(altered: 0.83));
      expect(r.verdict, isNot(VerificationVerdict.real));
      expect(
          r.checks
              .firstWhere((c) => c.id == FeatureCheckId.surfaceAnomaly)
              .failed,
          isTrue);
    });

    test('one serial unread → unable to verify', () {
      final r = engine.evaluate(analysis(serials: ['AK4718263', '']));
      expect(r.verdict, VerificationVerdict.unableToVerify);
    });

    test('year not read → unable to verify, not fake', () {
      final r = engine.evaluate(analysis(year: null));
      expect(r.verdict, VerificationVerdict.unableToVerify);
    });

    test('rejection reasons reach the result', () {
      final r = engine.evaluate(const NoteAnalysisModel(
        isBanknote: false,
        banknoteConfidence: 0,
        rejectionReasons: ['FRONT: shape 1.41 : 1'],
      ));
      expect(r.verdict, VerificationVerdict.notBanknote);
      expect(r.messages, contains('FRONT: shape 1.41 : 1'));
    });
  });

  group('uncertain YOLO boxes', () {
    const sharp =
        ImageQualityModel(blurScore: 0.1, glareScore: 0.05, brightness: 0.5);

    VerificationResultModel withBackSeals(int confirmed, int uncertain) =>
        engine.evaluate(NoteAnalysisModel(
          isBanknote: true,
          banknoteConfidence: 0.9,
          front: const SideDetectionModel(
            quality: sharp,
            denomination: 5000,
            denominationConfidence: 0.9,
            sbpSeals: FeatureDetectionModel(count: 1, confidence: 0.9),
            securityThreads: FeatureDetectionModel(count: 1, confidence: 0.9),
            securityLines: FeatureDetectionModel(count: 0, confidence: 1),
            securityDots: FeatureDetectionModel(count: 3, confidence: 0.9),
            printedYear:
                PrintedYearModel(detected: true, value: '2022', confidence: 0.9),
            serialNumbers: [
              SerialReadModel(text: 'AK4718263', confidence: 0.9),
              SerialReadModel(text: 'AK4718263', confidence: 0.9),
            ],
          ),
          back: SideDetectionModel(
            quality: sharp,
            denomination: 5000,
            denominationConfidence: 0.9,
            sbpSeals: FeatureDetectionModel(
                count: confirmed, confidence: 0.9, uncertainCount: uncertain),
          ),
          anomaly: const AnomalyModel(anomalyScore: 0.1),
        ));

    test('3 confirmed back seals pass', () {
      expect(withBackSeals(3, 0).verdict, VerificationVerdict.real);
    });

    test('2 confirmed + 1 low-confidence → unable to verify, not suspicious', () {
      expect(withBackSeals(2, 1).verdict, VerificationVerdict.unableToVerify);
    });

    test('2 confirmed and nothing else → suspicious', () {
      expect(withBackSeals(2, 0).verdict, VerificationVerdict.suspicious);
    });

    test('low-confidence boxes never add to a count', () {
      expect(withBackSeals(1, 5).verdict, isNot(VerificationVerdict.real));
    });
  });

  test('Rs 1000 thread only faintly seen → unable to verify, not suspicious', () {
    const q = ImageQualityModel(blurScore: 0.1, glareScore: 0.05, brightness: 0.5);
    final r = engine.evaluate(const NoteAnalysisModel(
      isBanknote: true,
      banknoteConfidence: 0.9,
      front: SideDetectionModel(
        quality: q,
        denomination: 1000,
        denominationConfidence: 0.96,
        sbpSeals: FeatureDetectionModel(count: 1, confidence: 0.69),
        securityThreads:
            FeatureDetectionModel(count: 0, confidence: 1, uncertainCount: 1),
        securityLines: FeatureDetectionModel(count: 0, confidence: 1),
        securityDots:
            FeatureDetectionModel(count: 1, confidence: 0.79, markCount: 2),
        printedYear:
            PrintedYearModel(detected: true, value: '2025', confidence: 0.7),
        serialNumbers: [
          SerialReadModel(text: 'ATG8159424', confidence: 0.9),
          SerialReadModel(text: 'ATG8159424', confidence: 0.9),
        ],
      ),
      back: SideDetectionModel(
        quality: q,
        denomination: 1000,
        denominationConfidence: 0.89,
        sbpSeals: FeatureDetectionModel(count: 3, confidence: 0.78),
      ),
    ));
    expect(r.verdict, VerificationVerdict.unableToVerify);
    final mark = r.checks.firstWhere((c) => c.id == FeatureCheckId.linesDots);
    expect(mark.status, CheckStatus.pass);
    expect(mark.summary, 'Security dots: 2 of 2 counted');
  });

  group('Rs 5,000 genuine/counterfeit CNN', () {
    const q = ImageQualityModel(blurScore: 0.1, glareScore: 0.05, brightness: 0.5);
    NoteAnalysisModel rs5000({
      double front = 0.05,
      double back = 0.05,
      String? notApplicable,
    }) =>
        NoteAnalysisModel(
          isBanknote: true,
          banknoteConfidence: 0.95,
          front: const SideDetectionModel(
            quality: q,
            denomination: 5000,
            denominationConfidence: 0.95,
            sbpSeals: FeatureDetectionModel(count: 1, confidence: 0.9),
            securityThreads: FeatureDetectionModel(count: 1, confidence: 0.9),
            securityLines: FeatureDetectionModel(count: 0, confidence: 1),
            securityDots: FeatureDetectionModel(count: 1, confidence: 0.9),
            printedYear:
                PrintedYearModel(detected: true, value: '2022', confidence: 0.9),
            serialNumbers: [
              SerialReadModel(text: 'AK4718263', confidence: 0.9),
              SerialReadModel(text: 'AK4718263', confidence: 0.9),
            ],
          ),
          back: const SideDetectionModel(
            quality: q,
            denomination: 5000,
            denominationConfidence: 0.95,
            sbpSeals: FeatureDetectionModel(count: 3, confidence: 0.9),
          ),
          anomaly: const AnomalyModel(anomalyScore: 0.05),
          counterfeitCnn: notApplicable != null
              ? null
              : CounterfeitCnnModel(frontCounterfeit: front, backCounterfeit: back),
          rs5000OnlyReason: notApplicable,
        );

    FeatureCheckModel cnn(VerificationResultModel r) =>
        r.checks.firstWhere((c) => c.id == FeatureCheckId.counterfeitCnn);

    test('genuine on both sides → passes', () {
      final r = engine.evaluate(rs5000());
      expect(cnn(r).status, CheckStatus.pass);
      expect(r.verdict, VerificationVerdict.real);
    });

    test('counterfeit ≥ 0.5 on either side → fails, never PASSED', () {
      final r = engine.evaluate(rs5000(back: 0.81));
      expect(cnn(r).status, CheckStatus.fail);
      expect(r.verdict, VerificationVerdict.suspicious);
    });

    test('other denominations → both CNN checks N/A, not partial', () {
      final r = engine.evaluate(rs5000(notApplicable: 'Only for Rs 5,000 notes'));
      expect(cnn(r).status, CheckStatus.notApplicable);
      expect(
        r.checks.firstWhere((c) => c.id == FeatureCheckId.surfaceAnomaly).status,
        CheckStatus.notApplicable,
      );
      expect(
        r.checks.any((c) =>
            c.status == CheckStatus.skipped &&
            c.id != FeatureCheckId.microprint &&
            c.id != FeatureCheckId.monument),
        isFalse,
      );
    });

    test('JSON round trip keeps the classifier output', () {
      final back = NoteAnalysisModel.fromJson(rs5000(back: 0.3).toJson());
      expect(back.counterfeitCnn!.backCounterfeit, closeTo(0.3, 1e-9));
    });
  });
}
