import 'package:fake_currency_detector/features/verification/data/on_device/image_preprocessor.dart';
import 'package:fake_currency_detector/features/verification/data/on_device/yolo_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  img.Image paper() =>
      img.Image(width: 400, height: 400)..clear(img.ColorRgb8(215, 205, 190));

  test('counts two stacked dots inside one box (Rs 1,000 layout)', () {
    final im = paper();
    img.fillCircle(im, x: 200, y: 160, radius: 14, color: img.ColorRgb8(40, 40, 90));
    img.fillCircle(im, x: 200, y: 240, radius: 14, color: img.ColorRgb8(40, 40, 90));
    expect(
      ImagePreprocessor.countMarksIn(im, const BoxRect(170, 130, 230, 270)),
      2,
    );
  });

  test('counts three dots (Rs 5,000 layout)', () {
    final im = paper();
    for (final y in [140, 200, 260]) {
      img.fillCircle(im, x: 200, y: y, radius: 12, color: img.ColorRgb8(30, 30, 30));
    }
    expect(
      ImagePreprocessor.countMarksIn(im, const BoxRect(175, 115, 225, 285)),
      3,
    );
  });

  test('counts two dash lines (Rs 50 layout)', () {
    final im = paper();
    img.fillRect(im, x1: 150, y1: 180, x2: 250, y2: 192, color: img.ColorRgb8(50, 40, 40));
    img.fillRect(im, x1: 150, y1: 215, x2: 250, y2: 227, color: img.ColorRgb8(50, 40, 40));
    expect(
      ImagePreprocessor.countMarksIn(im, const BoxRect(140, 170, 260, 237)),
      2,
    );
  });

  test('ignores fine speckle noise', () {
    final im = paper();
    for (var i = 0; i < 30; i++) {
      im.setPixelRgb(150 + i * 3, 200 + (i % 5), 20, 20, 20);
    }
    img.fillCircle(im, x: 200, y: 200, radius: 15, color: img.ColorRgb8(30, 30, 60));
    expect(
      ImagePreprocessor.countMarksIn(im, const BoxRect(140, 170, 260, 230)),
      1,
    );
  });
}
