import 'dart:io';

import 'package:fake_currency_detector/features/verification/data/on_device/image_preprocessor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('prep_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  img.Image checkerboard(int w, int h) {
    final im = img.Image(width: w, height: h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final on = ((x ~/ 6) + (y ~/ 6)).isEven;
        im.setPixelRgb(x, y, on ? 230 : 30, on ? 200 : 40, on ? 180 : 60);
      }
    }
    return im;
  }

  PreparedImage prep(img.Image im) =>
      ImagePreprocessor.prepareSync(img.encodePng(im));

  test('YOLO input is 3x640x640 channels-first, 0–1, with 114 padding', () {
    final p = prep(checkerboard(800, 400));
    const plane = 640 * 640;
    expect(p.yoloInput.length, 3 * plane);
    // 800x400 → 640x320, padded 160 px top and bottom.
    expect(p.letterbox.scale, closeTo(0.8, 1e-9));
    expect(p.letterbox.padX, 0);
    expect(p.letterbox.padY, 160);
    expect(p.yoloInput[0], closeTo(114 / 255, 1e-6)); // R plane, pad
    expect(p.yoloInput[2 * plane], closeTo(114 / 255, 1e-6)); // B plane, pad
    expect(p.yoloInput.every((v) => v >= 0 && v <= 1), isTrue);
  });

  test('R, G and B planes are kept separate', () {
    final solid = img.Image(width: 640, height: 640)
      ..clear(img.ColorRgb8(255, 0, 51));
    final p = prep(solid);
    const plane = 640 * 640;
    expect(p.yoloInput[1000], closeTo(1, 1e-6));
    expect(p.yoloInput[plane + 1000], closeTo(0, 1e-6));
    expect(p.yoloInput[2 * plane + 1000], closeTo(0.2, 1e-6));
  });

  test('CNN input is 224x224x3 in 0–255', () {
    final p = prep(checkerboard(800, 400));
    expect(p.cnnInput.length, 224 * 224 * 3);
    expect(p.cnnInput.every((v) => v >= 0 && v <= 255), isTrue);
  });

  test('working image is kept in memory and capped at 2048', () {
    final p = prep(checkerboard(3000, 1500));
    expect(p.width, 2048);
    expect(p.height, 1024);
    expect(p.pixels.rgba.length, 2048 * 1024 * 4);
  });

  test('blurred image scores blurrier than a sharp one', () {
    final sharp = prep(checkerboard(800, 400));
    final blurred = prep(img.gaussianBlur(checkerboard(800, 400), radius: 12));
    expect(sharp.quality.isUsable, isTrue);
    expect(blurred.quality.blurScore, greaterThan(sharp.quality.blurScore));
  });
}
