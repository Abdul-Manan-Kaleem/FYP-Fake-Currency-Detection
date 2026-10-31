import 'dart:io';
import 'dart:typed_data';

import 'package:fake_currency_detector/features/verification/data/on_device/image_preprocessor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// The Rs 5,000 genuine/counterfeit CNN was trained on torchvision
/// `Resize((224, 224))`, i.e. Pillow's antialiased BILINEAR resize. The
/// fixture was produced by real Pillow (scratch script `fixture.py`).
void main() {
  test('Dart resize matches Pillow BILINEAR on a 911x413 image', () {
    final src = img.decodePng(File('test/fixtures/pil_resize_src.png').readAsBytesSync())!;
    final expected = Uint8List.fromList(
        File('test/fixtures/pil_resize_224.rgb').readAsBytesSync());

    final got = ImagePreprocessor.pilBilinearRgb(src, 224, 224);

    expect(got.length, expected.length);
    var maxDiff = 0.0, exact = 0;
    for (var i = 0; i < got.length; i++) {
      final d = (got[i] - expected[i]).abs();
      if (d > maxDiff) maxDiff = d;
      if (d == 0) exact++;
    }
    // ignore: avoid_print
    print('max |diff| = $maxDiff, exact ${(100 * exact / got.length).toStringAsFixed(2)}%');
    expect(maxDiff, lessThanOrEqualTo(1));
    expect(exact / got.length, greaterThan(0.99));
  });
}
