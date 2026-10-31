import '../../domain/side_classifier.dart';
import 'monument_classifier.dart';
import 'yolo_decoder.dart';

/// Front/back decision from YOLO11s features (no extra model).
///
/// - Front (Quaid-e-Azam side): serial numbers, printed year, security
///   thread, security lines or dots. All of these are labelled on the front
///   only.
/// - Back (building side): SBP seals (3) and none of the front-only features.
abstract final class NoteSideRules {
  static const Set<YoloClass> frontOnly = {
    YoloClass.serialNumber,
    YoloClass.printedYear,
    YoloClass.securityThread,
    YoloClass.securityLines,
    YoloClass.securityDots,
  };

  /// Boxes this weak are ignored for the side decision.
  static const double minScore = 0.35;

  /// Monument predictions used for side decisions and wrong-note pop-ups
  /// must be very confident: in held-out tests the model read a few worn
  /// Rs 10 FRONTS as Rs 10 backs at 0.54–0.82. (The monument check on the
  /// back itself keeps its 0.60 threshold.)
  static const double monumentConfidence = 0.90;

  /// YOLO features decide; a confident monument (back-side only) breaks
  /// a tie when YOLO is unsure.
  static DetectedSide classify(
    List<YoloDetection> dets, [
    MonumentPrediction? monument,
  ]) {
    final strong = dets.where((d) => d.score >= minScore).toList();
    final frontKinds =
        strong.where((d) => frontOnly.contains(d.cls)).map((d) => d.cls).toSet();
    final seals = strong.where((d) => d.cls == YoloClass.sbpSeal).length;

    if (frontKinds.length >= 2) return DetectedSide.front;
    if (frontKinds.isEmpty && seals >= 2) return DetectedSide.back;
    if (frontKinds.isEmpty &&
        monument != null &&
        monument.denomination != null &&
        monument.confidence >= monumentConfidence) {
      return DetectedSide.back;
    }
    return DetectedSide.unknown;
  }
}
