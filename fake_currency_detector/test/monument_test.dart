import 'package:fake_currency_detector/features/scanner/domain/capture_models.dart';
import 'package:fake_currency_detector/features/verification/data/models/feature_check_model.dart';
import 'package:fake_currency_detector/features/verification/data/models/note_analysis_model.dart';
import 'package:fake_currency_detector/features/verification/data/models/verification_result_model.dart';
import 'package:fake_currency_detector/features/verification/data/on_device/monument_classifier.dart';
import 'package:fake_currency_detector/features/verification/data/on_device/native_decoder.dart';
import 'package:fake_currency_detector/features/verification/data/on_device/note_side_classifier.dart';
import 'package:fake_currency_detector/features/verification/data/on_device/yolo_decoder.dart';
import 'package:fake_currency_detector/features/verification/domain/side_classifier.dart';
import 'package:fake_currency_detector/features/verification/domain/verification_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  final engine = VerificationEngine(clock: () => DateTime(2026, 10, 31));
  const q = ImageQualityModel(blurScore: 0.1, glareScore: 0.05, brightness: 0.5);

  /// A Rs 100 note that passes every physical check.
  NoteAnalysisModel rs100(MonumentResultModel? monument) => NoteAnalysisModel(
        isBanknote: true,
        banknoteConfidence: 0.95,
        front: const SideDetectionModel(
          quality: q,
          denomination: 100,
          denominationConfidence: 0.95,
          sbpSeals: FeatureDetectionModel(count: 1, confidence: 0.9),
          securityThreads: FeatureDetectionModel(count: 1, confidence: 0.9),
          securityLines: FeatureDetectionModel(count: 1, confidence: 0.9),
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
        monument: monument,
      );

  FeatureCheckModel check(VerificationResultModel r) =>
      r.checks.firstWhere((c) => c.id == FeatureCheckId.monument);

  group('labels', () {
    test('Teachable Machine labels.txt is parsed', () {
      expect(
        Monuments.parseLabels('0 monument_10\n1 monument_20\r\n7 invalid\n'),
        ['monument_10', 'monument_20', 'invalid'],
      );
    });

    test('label to denomination', () {
      expect(Monuments.denominationOf('monument_100'), 100);
      expect(Monuments.denominationOf('monument_5000'), 5000);
      expect(Monuments.denominationOf('invalid'), isNull);
      expect(Monuments.denominationOf('monument_75'), isNull);
    });

    test('all seven monuments are mapped', () {
      expect(Monuments.byDenomination[100], 'Ziarat Residency');
      expect(Monuments.byDenomination[5000], 'Faisal Mosque');
      expect(Monuments.byDenomination.length, 7);
      expect(Monuments.classNames.length, 8);
    });
  });

  group('engine', () {
    test('right monument: PASS, Ziarat Residency matched', () {
      final r = engine.evaluate(rs100(const MonumentResultModel(
          modelAvailable: true, verified: true, label: 'monument_100', confidence: 0.91)));
      expect(check(r).status, CheckStatus.pass);
      expect(check(r).summary, 'Back side verified – Ziarat Residency matched');
      expect(r.verdict, VerificationVerdict.real);
    });

    test('wrong monument at 0.60+ is FAKE even if everything else passes', () {
      final r = engine.evaluate(rs100(const MonumentResultModel(
          modelAvailable: true, verified: true, label: 'monument_5000', confidence: 0.83)));
      expect(check(r).status, CheckStatus.fail);
      expect(r.verdict, VerificationVerdict.fake);
      expect(r.messages.first,
          'Fake Note – Backside monument mismatch. 100 rupay pe Ziarat Residency honi chahiye.');
      expect(r.messages[1], 'Back side galat hai – Ye 100 ka asli note nahi lag raha.');
    });

    test('invalid (blurry copy / no monument) at 0.60+ is FAKE', () {
      final r = engine.evaluate(rs100(const MonumentResultModel(
          modelAvailable: true, verified: true, label: 'invalid', confidence: 0.7)));
      expect(r.verdict, VerificationVerdict.fake);
    });

    test('confidence below 0.60 never fails and asks for a clearer photo', () {
      final r = engine.evaluate(rs100(const MonumentResultModel(
          modelAvailable: true, verified: true, label: 'monument_5000', confidence: 0.45)));
      expect(check(r).status, CheckStatus.skipped);
      expect(check(r).summary, startsWith('Thora saaf photo lein, monument clear nahi'));
      expect(r.verdict, VerificationVerdict.real);
    });

    test('unverified model: mismatch is only a WARNING, never FAKE', () {
      final r = engine.evaluate(rs100(const MonumentResultModel(
          modelAvailable: true, label: 'monument_5000', confidence: 0.95)));
      expect(check(r).status, CheckStatus.warning);
      expect(check(r).summary, contains('preliminary model'));
      expect(r.verdict, VerificationVerdict.real);
    });

    test('denomination the model was not trained on: not checked', () {
      final r = engine.evaluate(rs100(const MonumentResultModel(
          modelAvailable: true,
          verified: true,
          label: 'monument_5000',
          confidence: 0.95,
          knownDenominations: [1000, 5000])));
      expect(check(r).status, CheckStatus.skipped);
      expect(check(r).summary, contains('not trained on Rs 100'));
      expect(r.verdict, VerificationVerdict.real);
    });

    test('model not installed: not checked, nothing breaks', () {
      final r = engine.evaluate(rs100(const MonumentResultModel.notInstalled()));
      expect(check(r).status, CheckStatus.skipped);
      expect(check(r).summary, contains('not installed'));
      expect(r.verdict, VerificationVerdict.real);
    });
  });

  group('side check with the monument', () {
    YoloDetection d(YoloClass c, [double s = 0.8]) =>
        YoloDetection(c, s, const BoxRect(0, 0, 10, 10));
    const m5000 = MonumentPrediction(
        label: 'monument_5000', confidence: 0.9, probabilities: {});

    test('YOLO unsure + confident monument means back', () {
      expect(NoteSideRules.classify([d(YoloClass.rs5000, 0.6)], m5000), DetectedSide.back);
    });

    test('front-only features win over a monument guess', () {
      expect(
        NoteSideRules.classify(
            [d(YoloClass.serialNumber), d(YoloClass.printedYear)], m5000),
        DetectedSide.front,
      );
    });

    test('wrong-note message', () {
      final e = SideError.wrongNote(found: 5000, scanning: 1000);
      expect(e.urdu, 'Ye 5000 ka note hai, aap 1000 scan kar rahe hain.');
      expect(e.english, isNotEmpty);
    });
  });

  test('letterbox input keeps the whole image on grey 114', () {
    // 400x200 white image → 224x112 band centred, grey above and below.
    final im = img.Image(width: 400, height: 200)..clear(img.ColorRgb8(255, 255, 255));
    final f = MonumentClassifier.teachableMachineInput(
            RgbaImage.fromImage(im), 224, false, letterbox: true)
        .buffer
        .asFloat32List();
    double at(int x, int y) => f[(y * 224 + x) * 3];
    expect(at(112, 0), closeTo(114 / 127.5 - 1, 1e-6)); // top padding
    expect(at(112, 112), closeTo(1, 1e-6)); // image
    expect(at(112, 223), closeTo(114 / 127.5 - 1, 1e-6)); // bottom padding
    expect(at(0, 112), closeTo(1, 1e-6)); // full width kept
  });

  test('Teachable Machine input: centre square crop, 224, float in [-1, 1]', () {
    // 400x200: left half black, right half white, so the centre square is
    // half black, half white.
    final im = img.Image(width: 400, height: 200);
    for (var y = 0; y < 200; y++) {
      for (var x = 0; x < 400; x++) {
        final v = x < 200 ? 0 : 255;
        im.setPixelRgb(x, y, v, v, v);
      }
    }
    final bytes = MonumentClassifier.teachableMachineInput(
        RgbaImage.fromImage(im), 224, false);
    final f = bytes.buffer.asFloat32List();
    expect(f.length, 224 * 224 * 3);
    expect(f.first, closeTo(-1, 1e-6)); // top-left: black
    expect(f[(224 * 224 - 1) * 3], closeTo(1, 1e-6)); // bottom-right: white
    final q8 = MonumentClassifier.teachableMachineInput(RgbaImage.fromImage(im), 224, true);
    expect(q8.length, 224 * 224 * 3);
  });
}
