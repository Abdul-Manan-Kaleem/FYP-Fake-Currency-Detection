import 'dart:io';

import 'package:fake_currency_detector/features/scanner/data/photo_enhancer.dart';
import 'package:fake_currency_detector/features/scanner/domain/capture_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  CapturedImage photo({String? enhanced}) => CapturedImage(
        path: 'orig.jpg',
        side: NoteSide.front,
        source: CaptureSource.camera,
        capturedAt: DateTime(2026, 11, 24),
        enhancedPath: enhanced,
      );

  group('manual Enhance switch', () {
    test('OFF by default: the original photo is the one checked', () {
      const s = CaptureState();
      expect(s.enhance, isFalse);
      final c = CaptureState(front: photo(enhanced: 'orig_enhanced.jpg'));
      expect(c.frontToUse!.path, 'orig.jpg');
    });

    test('ON uses the enhanced copy, OFF goes back to the original', () {
      final p = photo(enhanced: 'orig_enhanced.jpg');
      expect(p.chosen(true).path, 'orig_enhanced.jpg');
      expect(p.chosen(false).path, 'orig.jpg');
    });

    test('ON without a copy falls back to the original', () {
      expect(photo().chosen(true).path, 'orig.jpg');
    });

    test('copyWith keeps and changes the switch', () {
      final on = const CaptureState().copyWith(enhance: true);
      expect(on.enhance, isTrue);
      expect(on.copyWith(busy: true).enhance, isTrue);
      expect(on.copyWith(enhance: false).enhance, isFalse);
    });
  });

  test('enhancing makes a new file and never changes the original', () {
    final dir = Directory.systemTemp.createTempSync('enh');
    addTearDown(() => dir.deleteSync(recursive: true));
    // Low-contrast grey photo.
    final im = img.Image(width: 40, height: 40);
    for (var y = 0; y < 40; y++) {
      for (var x = 0; x < 40; x++) {
        final v = 100 + (x ~/ 4);
        im.setPixelRgb(x, y, v, v, v);
      }
    }
    final orig = File('${dir.path}/note.jpg')..writeAsBytesSync(img.encodeJpg(im));
    final before = orig.readAsBytesSync();

    final out = PhotoEnhancer.enhanceSync(orig.path);

    expect(out, isNot(orig.path));
    expect(out, endsWith('_enhanced.jpg'));
    expect(orig.readAsBytesSync(), before); // original untouched
    final e = img.decodeJpg(File(out).readAsBytesSync())!;
    final lo = e.getPixel(0, 0).r, hi = e.getPixel(39, 0).r;
    expect(hi - lo, greaterThan(150)); // contrast stretched
  });
}
