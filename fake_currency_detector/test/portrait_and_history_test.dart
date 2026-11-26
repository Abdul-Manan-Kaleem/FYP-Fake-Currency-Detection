import 'package:fake_currency_detector/features/history/data/scan_record.dart';
import 'package:fake_currency_detector/features/history/domain/csv_export.dart';
import 'package:fake_currency_detector/features/verification/data/models/feature_check_model.dart';
import 'package:fake_currency_detector/features/verification/data/models/note_analysis_model.dart';
import 'package:fake_currency_detector/features/verification/data/models/verification_result_model.dart';
import 'package:fake_currency_detector/features/verification/data/on_device/portrait_classifier.dart';
import 'package:fake_currency_detector/features/verification/domain/verification_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final engine = VerificationEngine(clock: () => DateTime(2026, 11, 25));
  const q = ImageQualityModel(blurScore: 0.1, glareScore: 0.05, brightness: 0.5);

  const goodMonument = MonumentResultModel(
      modelAvailable: true, verified: true, label: 'monument_100', confidence: 0.91);

  /// A Rs 100 note that passes every physical check and the monument check.
  NoteAnalysisModel rs100(PortraitResultModel? portrait) => NoteAnalysisModel(
        isBanknote: true,
        banknoteConfidence: 0.95,
        front: const SideDetectionModel(
          quality: q,
          denomination: 100,
          denominationConfidence: 0.95,
          sbpSeals: FeatureDetectionModel(count: 1, confidence: 0.9),
          securityThreads: FeatureDetectionModel(count: 1, confidence: 0.9),
          securityLines: FeatureDetectionModel(count: 3, confidence: 0.9),
          securityDots: FeatureDetectionModel(count: 0, confidence: 1),
          printedYear: PrintedYearModel(detected: true, value: '2022', confidence: 0.9),
          serialNumbers: [
            SerialReadModel(text: 'AK4718263', confidence: 0.9),
            SerialReadModel(text: 'AK4718263', confidence: 0.9),
          ],
        ),
        back: const SideDetectionModel(
          quality: q,
          denomination: 100,
          denominationConfidence: 0.95,
          sbpSeals: FeatureDetectionModel(count: 3, confidence: 0.9),
        ),
        rs5000OnlyReason: 'Only for Rs 5,000 notes',
        monument: goodMonument,
        portrait: portrait,
      );

  FeatureCheckModel portraitCheck(VerificationResultModel r) =>
      r.checks.firstWhere((c) => c.id == FeatureCheckId.portrait);

  group('portrait labels', () {
    test('label to denomination', () {
      expect(Portraits.denominationOf('portrait_100'), 100);
      expect(Portraits.denominationOf('portrait_5000'), 5000);
      expect(Portraits.denominationOf('invalid'), isNull);
      expect(Portraits.denominationOf('portrait_75'), isNull);
    });

    test('all seven values plus invalid', () {
      expect(Portraits.classNames.length, 8);
    });
  });

  group('portrait check', () {
    test('right portrait: PASS and the note stays REAL', () {
      final r = engine.evaluate(rs100(const PortraitResultModel(
          modelAvailable: true, verified: true, label: 'portrait_100', confidence: 0.93)));
      expect(portraitCheck(r).status, CheckStatus.pass);
      expect(portraitCheck(r).summary, contains('Quaid-e-Azam portrait matched'));
      expect(r.verdict, VerificationVerdict.real);
    });

    test('wrong portrait design at 0.60+ is FAKE even if all else passes', () {
      final r = engine.evaluate(rs100(const PortraitResultModel(
          modelAvailable: true, verified: true, label: 'portrait_5000', confidence: 0.84)));
      expect(portraitCheck(r).status, CheckStatus.fail);
      expect(r.verdict, VerificationVerdict.fake);
      expect(r.messages.first, contains('Quaid-e-Azam portrait'));
    });

    test('invalid (not a front) at 0.60+ is FAKE', () {
      final r = engine.evaluate(rs100(const PortraitResultModel(
          modelAvailable: true, verified: true, label: 'invalid', confidence: 0.8)));
      expect(r.verdict, VerificationVerdict.fake);
    });

    test('confidence below 0.60 never fails', () {
      final r = engine.evaluate(rs100(const PortraitResultModel(
          modelAvailable: true, verified: true, label: 'portrait_5000', confidence: 0.4)));
      expect(portraitCheck(r).status, CheckStatus.skipped);
      expect(r.verdict, VerificationVerdict.real);
    });

    test('preliminary (unverified) model: only a warning', () {
      final r = engine.evaluate(rs100(const PortraitResultModel(
          modelAvailable: true, label: 'portrait_5000', confidence: 0.95)));
      expect(portraitCheck(r).status, CheckStatus.warning);
      expect(r.verdict, VerificationVerdict.real);
    });

    test('model not installed: not checked, nothing breaks', () {
      final r = engine.evaluate(rs100(const PortraitResultModel.notInstalled()));
      expect(portraitCheck(r).status, CheckStatus.skipped);
      expect(r.verdict, VerificationVerdict.real);
    });

    test('portrait and monument both appear in the checks list', () {
      final r = engine.evaluate(rs100(const PortraitResultModel(
          modelAvailable: true, verified: true, label: 'portrait_100', confidence: 0.9)));
      expect(r.checks.map((c) => c.id),
          containsAll([FeatureCheckId.portrait, FeatureCheckId.monument]));
    });

    test('portrait result survives a JSON round trip', () {
      final a = rs100(const PortraitResultModel(
          modelAvailable: true, verified: true, label: 'portrait_100', confidence: 0.9));
      final b = NoteAnalysisModel.fromJson(a.toJson());
      expect(b.portrait!.label, 'portrait_100');
      expect(b.portrait!.denomination, 100);
    });
  });

  group('portrait face check (genuine Quaid-e-Azam vs changed)', () {
    PortraitResultModel face(String? label, double conf,
            {bool verified = true,
            String design = 'portrait_100',
            double designConf = 0.93}) =>
        PortraitResultModel(
          modelAvailable: true,
          verified: true,
          label: design,
          confidence: designConf,
          faceAvailable: true,
          faceLabel: label,
          faceConfidence: conf,
          faceVerified: verified,
        );

    test('genuine face and right design: PASS, note stays REAL', () {
      final r = engine.evaluate(rs100(face('genuine', 0.95)));
      expect(portraitCheck(r).status, CheckStatus.pass);
      expect(r.verdict, VerificationVerdict.real);
    });

    test('another person / glasses / earrings / nose pin / expression: FAIL, FAKE', () {
      final r = engine.evaluate(rs100(face('tampered', 0.88)));
      expect(portraitCheck(r).status, CheckStatus.fail);
      expect(portraitCheck(r).summary, contains('not the genuine Quaid-e-Azam portrait'));
      expect(r.verdict, VerificationVerdict.fake);
    });

    test('tampered even when the front design matches is still FAKE', () {
      final r = engine.evaluate(rs100(face('tampered', 0.75, design: 'portrait_100', designConf: 0.99)));
      expect(r.verdict, VerificationVerdict.fake);
    });

    test('tampered below 60% is not a fail (take a clearer photo)', () {
      final r = engine.evaluate(rs100(face('tampered', 0.55)));
      expect(portraitCheck(r).status, CheckStatus.skipped);
      expect(r.verdict, VerificationVerdict.real);
    });

    test('unverified face model only warns', () {
      final r = engine.evaluate(rs100(face('tampered', 0.9, verified: false)));
      expect(portraitCheck(r).status, CheckStatus.warning);
    });

    test('a wrong front design still fails even if the face looks genuine', () {
      final r = engine.evaluate(rs100(face('genuine', 0.95, design: 'portrait_5000', designConf: 0.9)));
      expect(portraitCheck(r).status, CheckStatus.fail);
      expect(r.verdict, VerificationVerdict.fake);
    });

    test('face result survives a JSON round trip', () {
      final a = rs100(face('tampered', 0.8));
      final b = NoteAnalysisModel.fromJson(a.toJson());
      expect(b.portrait!.faceAvailable, isTrue);
      expect(b.portrait!.faceLabel, 'tampered');
      expect(b.portrait!.faceConfidence, closeTo(0.8, 1e-9));
    });
  });

  group('scan history', () {
    VerificationResultModel result() => engine.evaluate(rs100(const PortraitResultModel(
        modelAvailable: true, verified: true, label: 'portrait_100', confidence: 0.93)));

    test('a record keeps time, denomination, verdict, score and features', () {
      final rec = ScanRecord.fromResult(result());
      expect(rec.scannedAt, DateTime(2026, 11, 25));
      expect(rec.denomination, 100);
      expect(rec.verdict, 'real');
      expect(rec.confidencePct, greaterThanOrEqualTo(85));
      expect(rec.features['portrait'], 'pass');
      expect(rec.features['monument'], 'pass');
      expect(rec.features['linesDots'], 'pass');
    });

    test('record survives a database row round trip', () {
      final rec = ScanRecord.fromResult(result());
      final back = ScanRecord.fromMap({'id': 7, ...rec.toMap()});
      expect(back.id, 7);
      expect(back.verdict, rec.verdict);
      expect(back.confidencePct, rec.confidencePct);
      expect(back.features, rec.features);
    });

    test('CSV cells are escaped', () {
      expect(csvCell('plain'), 'plain');
      expect(csvCell('a,b'), '"a,b"');
      expect(csvCell('say "hi"'), '"say ""hi"""');
      expect(csvCell(null), '');
    });

    test('CSV has a header and one row per scan, same column count', () {
      final rec = ScanRecord.fromResult(result());
      final csv = scansToCsv([rec, rec]);
      final lines = csv.trim().split('\r\n');
      expect(lines.length, 3);
      expect(lines.first, startsWith('id,timestamp,denomination_rs,final_result'));
      expect(lines.first, contains('portrait'));
      expect(lines.first, contains('monument'));
      expect(csvHeader().length, csvRow(rec).length);
    });
  });
}
