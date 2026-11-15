/// Checks that a photo really shows a banknote, not a page or random object.
///
/// In: the list of YOLO detections for one side. Out: true/false, or a
/// text reason why the side was rejected. Uses the YOLO11s results only;
/// it runs no model itself.
library;

import 'yolo_decoder.dart';

/// Decides whether YOLO actually sees a banknote on one side.
///
/// A note class alone is not enough: on test images YOLO11s gave
/// "500Rs Note 0.79" to a beige striped graphic and "100Rs Note 0.48" to a
/// page of printed text, each as one box covering the whole frame. None of
/// those images produced any security-feature box, while every real front
/// carries several (seal, serials, year, thread, lines/dots) and every back
/// carries SBP seals. So a side counts as a note only when YOLO also finds
/// security features on it.
abstract final class NotePresence {
  /// The six security-feature classes that prove a real note is present.
  static const Set<YoloClass> featureClasses = {
    YoloClass.sbpSeal,
    YoloClass.securityThread,
    YoloClass.serialNumber,
    YoloClass.printedYear,
    YoloClass.securityLines,
    YoloClass.securityDots,
  };

  /// Quick check used right after the first photo: does the image show a
  /// banknote at all? True when YOLO sees a note class and at least one
  /// security feature. A page, a face or a random object fails, so the user
  /// is told straight away instead of being asked for the back side.
  static bool looksLikeNote(List<YoloDetection> detections) =>
      detections.any((d) => d.cls.isNote) &&
      detections.any((d) => featureClasses.contains(d.cls));

  /// Different feature types needed on a front (it carries many).
  static const int minFrontFeatureTypes = 2;

  /// Different feature types needed on a back (mostly just SBP seals).
  static const int minBackFeatureTypes = 1;

  /// Null when [detections] look like a banknote side, otherwise the reason.
  static String? rejection(
    List<YoloDetection> detections, {
    required bool isFront,
  }) {
    final side = isFront ? 'FRONT' : 'BACK';
    // Step 1: find the most confident note box; reject if there is none.
    final note = detections
        .where((d) => d.cls.isNote)
        .fold<YoloDetection?>(null, (b, d) => b == null || d.score > b.score ? d : b);
    if (note == null) return '$side: YOLO11s found no banknote';

    // Step 2: count the different security-feature types and compare with
    // the minimum for this side.
    final types = detections
        .where((d) => featureClasses.contains(d.cls))
        .map((d) => d.cls)
        .toSet();
    final needed = isFront ? minFrontFeatureTypes : minBackFeatureTypes;
    if (types.length < needed) {
      return '$side: no banknote security features found '
          '(only "${note.cls.label}" ${note.score.toStringAsFixed(2)} '
          'over the whole image)';
    }
    return null;
  }
}
