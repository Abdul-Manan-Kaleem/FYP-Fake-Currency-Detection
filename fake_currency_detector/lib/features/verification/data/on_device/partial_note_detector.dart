/// Partial-note check based on the photo's shape.
///
/// In: the image's aspect ratio (long edge / short edge) and YOLO's best
/// denomination and score. Out: a reason text if the note looks cut off,
/// otherwise null. No model: it compares against known note sizes.
///
/// Detects a half / partial note (or a crop with lots of background) from the
/// shape of the image, so only whole notes are analysed.
///
/// Pakistani notes are all 65 mm tall and grow 8 mm in length per
/// denomination, so each one has a known shape. The ML Kit scanner and the
/// free crop both cut the image at the note's edges, so the image shape
/// should match. Half a note is roughly square; a top or bottom strip is very
/// long and thin.
abstract final class PartialNoteDetector {
  /// Length × height in mm.
  static const Map<int, (int, int)> noteSizesMm = {
    10: (115, 65),
    20: (123, 65),
    50: (131, 65),
    100: (139, 65),
    500: (147, 65),
    1000: (155, 65),
    5000: (163, 65),
  };

  /// Allowed deviation from the note's real shape. A little background in a
  /// manual crop stays inside this; a missing quarter or half does not.
  /// Below 80% of the expected aspect ratio = part of the note is missing.
  static const double tooShortFactor = 0.80;

  /// Above 120% of the expected aspect ratio = top or bottom cut off.
  static const double tooLongFactor = 1.20;

  /// Used when YOLO is not sure of the denomination (< 0.5).
  static const double genericMinAspect = 1.60;
  static const double genericMaxAspect = 2.90;

  /// Advice lines shown to the user when a side is rejected.
  static const List<String> guidance = [
    'What to do:',
    '1. Make sure the WHOLE note is in the photo: all four corners visible.',
    '2. Do not fold or cover any part of the note.',
    '3. Crop to the note\'s own edges (not inside them, not far outside).',
    '4. Scan again: front first, then the back.',
  ];

  /// Real length / height of [denomination] (e.g. 163 / 65 for Rs 5,000),
  /// or null if the denomination is unknown.
  static double? expectedAspect(int? denomination) {
    final size = noteSizesMm[denomination];
    return size == null ? null : size.$1 / size.$2;
  }

  /// Reason this side looks like part of a note, or null if whole.
  ///
  /// [aspectRatio] is long edge / short edge of the image. [denomination] is
  /// YOLO's best note class and [noteScore] its confidence.
  static String? rejection({
    required String side,
    required double aspectRatio,
    int? denomination,
    double noteScore = 0,
  }) {
    // Step 1: trust the denomination only if YOLO is at least 50% sure;
    // otherwise use the wide generic range.
    final expected = noteScore >= 0.5 ? expectedAspect(denomination) : null;
    final min = expected != null ? expected * tooShortFactor : genericMinAspect;
    final max = expected != null ? expected * tooLongFactor : genericMaxAspect;
    final shape = '${aspectRatio.toStringAsFixed(2)} : 1';
    final full = expected == null
        ? 'a whole note is about 1.8–2.5 : 1'
        : 'a whole Rs $denomination is about ${expected.toStringAsFixed(2)} : 1';

    // Step 2: too square = half a note; too long and thin = a cut-off strip.
    if (aspectRatio < min) {
      return '$side: only part of the note is in the image (half or cut off). '
          'Image shape $shape, $full';
    }
    if (aspectRatio > max) {
      return '$side: the top or bottom of the note is cut off. '
          'Image shape $shape, $full';
    }
    return null;
  }
}
