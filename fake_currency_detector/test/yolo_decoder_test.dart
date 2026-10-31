import 'dart:typed_data';

import 'package:fake_currency_detector/features/verification/data/on_device/image_preprocessor.dart';
import 'package:fake_currency_detector/features/verification/data/on_device/yolo_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const a = YoloDecoder.anchors;

  /// Builds a [1, 17, 8400] channel-major output with the given anchors.
  Float32List output(List<(int, List<double>, int, double)> rows) {
    final out = Float32List(17 * a);
    for (final (i, box, cls, score) in rows) {
      for (var k = 0; k < 4; k++) {
        out[k * a + i] = box[k];
      }
      out[(4 + cls) * a + i] = score;
    }
    return out;
  }

  test('class ids match the exported metadata', () {
    expect(YoloClass.byId(4).label, '5000Rs Note');
    expect(YoloClass.byId(4).denomination, 5000);
    expect(YoloClass.byId(12).label, 'serial_number');
    expect(YoloClass.values.length, YoloDecoder.numClasses);
    expect(YoloClass.values.where((c) => c.isNote).length, 7);
  });

  test('normalized boxes are scaled to 640 input pixels', () {
    final d = YoloDecoder.decode(
      output([(0, [0.5, 0.5, 0.25, 0.1], 4, 0.9)]),
      normalized: true,
    );
    expect(d.single.cls, YoloClass.rs5000);
    expect(d.single.box.left, closeTo(240, 1e-3));
    expect(d.single.box.right, closeTo(400, 1e-3));
    expect(d.single.box.top, closeTo(288, 1e-3));
  });

  test('scores at or below 0.25 are dropped', () {
    final d = YoloDecoder.decode(
      output([(0, [0.5, 0.5, 0.1, 0.1], 8, 0.25)]),
      normalized: true,
    );
    expect(d, isEmpty);
  });

  test('NMS removes same-class overlaps but keeps other classes', () {
    final d = YoloDecoder.decode(
      output([
        (0, [0.5, 0.5, 0.2, 0.2], 8, 0.9),
        (1, [0.505, 0.5, 0.2, 0.2], 8, 0.8), // duplicate seal
        (2, [0.505, 0.5, 0.2, 0.2], 11, 0.7), // thread at the same place
        (3, [0.1, 0.1, 0.05, 0.05], 8, 0.6), // separate seal
      ]),
      normalized: true,
    );
    expect(d.where((x) => x.cls == YoloClass.sbpSeal).length, 2);
    expect(d.where((x) => x.cls == YoloClass.securityThread).length, 1);
  });

  test('letterbox maps boxes back to the image', () {
    const lb = Letterbox(scale: 0.5, padX: 0, padY: 80);
    final b = lb.toImage(const BoxRect(100, 180, 200, 280));
    expect(b.left, 200);
    expect(b.top, 200);
    expect(b.right, 400);
    expect(b.bottom, 400);
  });
}
