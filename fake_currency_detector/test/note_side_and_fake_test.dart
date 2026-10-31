import 'package:fake_currency_detector/features/scanner/domain/capture_models.dart';
import 'package:fake_currency_detector/features/verification/data/models/confidence_score_model.dart';
import 'package:fake_currency_detector/features/verification/data/models/feature_check_model.dart';
import 'package:fake_currency_detector/features/verification/data/models/note_analysis_model.dart';
import 'package:fake_currency_detector/features/verification/data/models/verification_result_model.dart';
import 'package:fake_currency_detector/features/verification/data/on_device/note_side_classifier.dart';
import 'package:fake_currency_detector/features/verification/data/on_device/yolo_decoder.dart';
import 'package:fake_currency_detector/features/verification/domain/side_classifier.dart';
import 'package:fake_currency_detector/features/verification/domain/verification_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  YoloDetection d(YoloClass c, [double s = 0.8]) =>
      YoloDetection(c, s, const BoxRect(0, 0, 10, 10));

  group('front / back from YOLO features', () {
    test('front: serials + year + thread (all notes with a thread)', () {
      expect(
        NoteSideRules.classify([
          d(YoloClass.rs5000, 0.95),
          d(YoloClass.serialNumber),
          d(YoloClass.serialNumber),
          d(YoloClass.printedYear),
          d(YoloClass.securityThread),
          d(YoloClass.sbpSeal),
        ]),
        DetectedSide.front,
      );
    });

    test('front of Rs 10 (no thread, no lines/dots): serials + year', () {
      expect(
        NoteSideRules.classify([
          d(YoloClass.rs10),
          d(YoloClass.serialNumber),
          d(YoloClass.printedYear),
        ]),
        DetectedSide.front,
      );
    });

    test('back: three seals and no front-only feature', () {
      expect(
        NoteSideRules.classify([
          d(YoloClass.rs1000, 0.89),
          d(YoloClass.sbpSeal, 0.93),
          d(YoloClass.sbpSeal, 0.78),
          d(YoloClass.sbpSeal, 0.93),
        ]),
        DetectedSide.back,
      );
    });

    test('weak front-only boxes do not turn a back into a front', () {
      expect(
        NoteSideRules.classify([
          d(YoloClass.sbpSeal),
          d(YoloClass.sbpSeal),
          d(YoloClass.sbpSeal),
          d(YoloClass.serialNumber, 0.2),
          d(YoloClass.printedYear, 0.3),
        ]),
        DetectedSide.back,
      );
    });

    test('nothing recognisable → unknown (analysis decides)', () {
      expect(NoteSideRules.classify([d(YoloClass.rs500, 0.6)]), DetectedSide.unknown);
      expect(NoteSideRules.classify(const []), DetectedSide.unknown);
    });
  });

  test('wrong-side messages are bilingual', () {
    expect(SideError.backOnFront.urdu, contains('back side hai'));
    expect(SideError.backOnFront.urdu, contains('Quaid wali side'));
    expect(SideError.frontOnBack.urdu, contains('Building wali side'));
    expect(SideError.sameSideTwice.urdu, contains('pehle hi scan kar li hai'));
    for (final e in [SideError.backOnFront, SideError.frontOnBack, SideError.sameSideTwice]) {
      expect(e.english, isNotEmpty);
    }
  });

  group('photocopy → Jaali Note / Fake', () {
    final engine = VerificationEngine(clock: () => DateTime(2026, 10, 31));

    test('any denomination on paper is FAKE with the Urdu message', () {
      final r = engine.evaluate(const NoteAnalysisModel(
        isBanknote: false,
        banknoteConfidence: 0,
        rejectionKind: 'photocopy',
        rejectionReasons: ['FRONT: white paper border / printer paper around the note'],
      ));
      expect(r.verdict, VerificationVerdict.fake);
      expect(r.verdict.label, 'JAALI NOTE / FAKE NOTE');
      expect(r.verdict.isConclusive, isTrue);
      expect(r.confidence.band, ScoreBand.counterfeit);
      expect(r.messages.first, contains('Ye photocopy lag rahi hai'));
      expect(r.messages.join(' '), isNot(contains('A4')));
    });

    test('a page with no note is still "not a note", not fake', () {
      final r = engine.evaluate(const NoteAnalysisModel(
        isBanknote: false,
        banknoteConfidence: 0,
        rejectionKind: 'no_note',
        rejectionReasons: ['FRONT: YOLO11s found no banknote'],
      ));
      expect(r.verdict, VerificationVerdict.notBanknote);
    });
  });

  test('Rs 5,000 passes with unreadable microprint and says so', () {
    final engine = VerificationEngine(clock: () => DateTime(2026, 10, 31));
    const q = ImageQualityModel(blurScore: 0.1, glareScore: 0.05, brightness: 0.5);
    final r = engine.evaluate(const NoteAnalysisModel(
      isBanknote: true,
      banknoteConfidence: 0.95,
      front: SideDetectionModel(
        quality: q,
        denomination: 5000,
        denominationConfidence: 0.95,
        sbpSeals: FeatureDetectionModel(count: 1, confidence: 0.9),
        securityThreads: FeatureDetectionModel(count: 1, confidence: 0.9),
        securityLines: FeatureDetectionModel(count: 0, confidence: 1),
        securityDots: FeatureDetectionModel(count: 1, confidence: 0.9),
        printedYear: PrintedYearModel(detected: true, value: '2022', confidence: 0.9),
        serialNumbers: [
          SerialReadModel(text: 'AK4718263', confidence: 0.9),
          SerialReadModel(text: 'AK4718263', confidence: 0.9),
        ],
      ),
      back: SideDetectionModel(
        quality: q,
        denomination: 5000,
        denominationConfidence: 0.95,
        sbpSeals: FeatureDetectionModel(count: 3, confidence: 0.9),
      ),
      anomaly: AnomalyModel(anomalyScore: 0.05),
      counterfeitCnn: CounterfeitCnnModel(frontCounterfeit: 0.05, backCounterfeit: 0.05),
      microprint: MicroprintModel(expected: 5000, occurrences: 0, source: 'scan'),
    ));
    expect(r.verdict, VerificationVerdict.real);
    expect(r.confidence.percentage, greaterThanOrEqualTo(85));
    expect(
      r.checks.firstWhere((c) => c.id == FeatureCheckId.microprint).status,
      CheckStatus.skipped,
    );
    expect(r.messages.join(' '), contains('Microprint unreadable – verified by alternate features'));
  });
}
