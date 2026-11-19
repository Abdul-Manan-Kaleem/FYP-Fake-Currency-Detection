/// Decides whether a photo shows the front or the back of a note.
///
/// In: YOLO11s detections (and optionally a monument prediction). Out: a
/// [DetectedSide] (front, back or unknown). Uses the YOLO results only; no
/// extra model.
library;

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
  /// Feature classes that only appear on the front.
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
    // Step 1: keep only confident boxes; count front-only feature types
    // and SBP seals.
    final strong = dets.where((d) => d.score >= minScore).toList();
    final frontKinds =
        strong.where((d) => frontOnly.contains(d.cls)).map((d) => d.cls).toSet();
    final seals = strong.where((d) => d.cls == YoloClass.sbpSeal).length;

    // Step 2: two or more front-only feature types means FRONT.
    if (frontKinds.length >= 2) return DetectedSide.front;
    // Step 3: no front features and at least 2 seals means BACK.
    if (frontKinds.isEmpty && seals >= 2) return DetectedSide.back;
    // Step 4: tie-break with a very confident monument (back only).
    if (frontKinds.isEmpty &&
        monument != null &&
        monument.denomination != null &&
        monument.confidence >= monumentConfidence) {
      return DetectedSide.back;
    }
    // Step 5: not enough evidence either way.
    return DetectedSide.unknown;
  }
}
