import 'dart:math' as math;
import 'dart:typed_data';

/// Class IDs exactly as embedded in the exported model's metadata.json.
enum YoloClass {
  rs1000(0, '1000Rs Note', denomination: 1000),
  rs100(1, '100Rs Note', denomination: 100),
  rs10(2, '10Rs Note', denomination: 10),
  rs20(3, '20Rs Note', denomination: 20),
  rs5000(4, '5000Rs Note', denomination: 5000),
  rs500(5, '500Rs Note', denomination: 500),
  rs50(6, '50Rs Note', denomination: 50),
  printedYear(7, 'printed_year'),
  sbpSeal(8, 'sbp_seal'),
  securityDots(9, 'security_dots'),
  securityLines(10, 'security_lines'),
  securityThread(11, 'security_thread'),
  serialNumber(12, 'serial_number');

  const YoloClass(this.id, this.label, {this.denomination});

  final int id;
  final String label;

  /// Set for the seven note classes, null for security-feature classes.
  final int? denomination;

  bool get isNote => denomination != null;

  static YoloClass byId(int id) => values[id];
}

/// Axis-aligned box in pixel coordinates of whatever image it refers to.
class BoxRect {
  const BoxRect(this.left, this.top, this.right, this.bottom);

  final double left, top, right, bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get area => math.max(0, width) * math.max(0, height);

  double iou(BoxRect o) {
    final w = math.min(right, o.right) - math.max(left, o.left);
    final h = math.min(bottom, o.bottom) - math.max(top, o.top);
    if (w <= 0 || h <= 0) return 0;
    final inter = w * h;
    return inter / (area + o.area - inter);
  }

  BoxRect map(double Function(double) fx, double Function(double) fy) =>
      BoxRect(fx(left), fy(top), fx(right), fy(bottom));

  @override
  String toString() => '[${left.toStringAsFixed(0)}, ${top.toStringAsFixed(0)}, '
      '${right.toStringAsFixed(0)}, ${bottom.toStringAsFixed(0)}]';
}

class YoloDetection {
  const YoloDetection(this.cls, this.score, this.box);

  final YoloClass cls;
  final double score;
  final BoxRect box;

  @override
  String toString() =>
      '${cls.id}:${cls.label} ${score.toStringAsFixed(3)} $box';
}

/// Decodes the raw `[1, 4 + nc, anchors]` Ultralytics head (no NMS in graph).
///
/// Mirrors Ultralytics `non_max_suppression` defaults used by
/// `model.predict()` in Colab: conf 0.25, IoU 0.7, class-aware, max 300.
abstract final class YoloDecoder {
  static const int numClasses = 13;
  static const int anchors = 8400;
  static const double defaultConf = 0.25;
  static const double defaultIou = 0.7;
  static const int maxDetections = 300;

  /// Highest score each class reached on any anchor, including scores below
  /// the 0.25 detection threshold. Used only to tell "faintly seen" apart
  /// from "not there at all"; never to create boxes.
  static List<double> classMax(Float32List output) => [
        for (var c = 0; c < numClasses; c++)
          () {
            var m = 0.0;
            final base = (4 + c) * anchors;
            for (var a = 0; a < anchors; a++) {
              if (output[base + a] > m) m = output[base + a];
            }
            return m;
          }(),
      ];

  /// [output] is channel-major: value(c, a) = output[c * anchors + a].
  /// Boxes are cx, cy, w, h; when [normalized] they are 0–1 of [inputSize].
  /// Returned boxes are in letterboxed input pixels (0..inputSize).
  static List<YoloDetection> decode(
    Float32List output, {
    required bool normalized,
    int inputSize = 640,
    double conf = defaultConf,
    double iou = defaultIou,
  }) {
    assert(output.length == (4 + numClasses) * anchors);
    final scale = normalized ? inputSize.toDouble() : 1.0;
    final candidates = <YoloDetection>[];

    for (var a = 0; a < anchors; a++) {
      var best = -1;
      var bestScore = conf;
      for (var c = 0; c < numClasses; c++) {
        final s = output[(4 + c) * anchors + a];
        if (s > bestScore) {
          bestScore = s;
          best = c;
        }
      }
      if (best < 0) continue;
      final cx = output[a] * scale;
      final cy = output[anchors + a] * scale;
      final w = output[2 * anchors + a] * scale;
      final h = output[3 * anchors + a] * scale;
      candidates.add(YoloDetection(
        YoloClass.byId(best),
        bestScore,
        BoxRect(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2),
      ));
    }

    candidates.sort((x, y) => y.score.compareTo(x.score));
    final kept = <YoloDetection>[];
    for (final d in candidates) {
      final suppressed = kept.any((k) => k.cls == d.cls && k.box.iou(d.box) > iou);
      if (!suppressed) kept.add(d);
      if (kept.length >= maxDetections) break;
    }
    return kept;
  }
}
