import 'package:fake_currency_detector/features/verification/data/on_device/note_presence.dart';
import 'package:fake_currency_detector/features/verification/data/on_device/yolo_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  YoloDetection d(YoloClass c, double s) =>
      YoloDetection(c, s, const BoxRect(0, 0, 10, 10));

  // Real outputs of the bundled YOLO11s on non-note test images.
  test('striped graphic seen as "500Rs Note 0.786" is rejected', () {
    final r = NotePresence.rejection([d(YoloClass.rs500, 0.786)], isFront: true);
    expect(r, contains('no banknote security features'));
  });

  test('page of text seen as 100Rs/1000Rs is rejected', () {
    final r = NotePresence.rejection(
      [d(YoloClass.rs100, 0.476), d(YoloClass.rs1000, 0.342)],
      isFront: false,
    );
    expect(r, isNotNull);
  });

  test('nothing detected is rejected', () {
    expect(NotePresence.rejection(const [], isFront: true),
        'FRONT: YOLO11s found no banknote');
  });

  test('front with note class and several feature types passes', () {
    expect(
      NotePresence.rejection([
        d(YoloClass.rs5000, 0.93),
        d(YoloClass.sbpSeal, 0.8),
        d(YoloClass.serialNumber, 0.9),
        d(YoloClass.serialNumber, 0.88),
      ], isFront: true),
      isNull,
    );
  });

  test('front with only one feature type is rejected', () {
    expect(
      NotePresence.rejection(
          [d(YoloClass.rs5000, 0.93), d(YoloClass.sbpSeal, 0.8)],
          isFront: true),
      isNotNull,
    );
  });

  test('back with note class and seals passes', () {
    expect(
      NotePresence.rejection(
          [d(YoloClass.rs5000, 0.9), d(YoloClass.sbpSeal, 0.7)],
          isFront: false),
      isNull,
    );
  });
}
