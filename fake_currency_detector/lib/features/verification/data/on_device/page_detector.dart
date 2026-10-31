/// Recognises printer paper (white border, page shape, blank paper) around a
/// note. With a note on it, this is a photocopy / printout and is reported
/// as FAKE ("Jaali Note"); a page with no note on it is "not a note".
///
/// Signals, all measured on device:
/// - shape: ML Kit crops to the object's edges, so a page comes out at
///   ≈1.41 : 1 (A-series) or ≈1.29 : 1 (letter); notes are ≈1.8–2.4 : 1
/// - paper white: share of bright, colourless pixels; notes are printed edge
///   to edge, a page is mostly blank paper
/// - note coverage: how much of the image YOLO's note box covers; a note
///   printed on a page covers only part of it
abstract final class PageDetector {
  static const double minPageAspect = 1.25;
  static const double maxPageAspect = 1.50;
  static const double pageWhite = 0.25;
  static const double blankWhite = 0.45;
  static const double minNoteCoverage = 0.60;

  static const List<String> guidance = [
    'What to do:',
    '1. Use the real banknote, not a page, printout or photocopy.',
    '2. Put the note alone on a dark, plain surface (table or cloth).',
    '3. Fill the frame with the note so the scanner crops to its edges.',
    '4. Use even light without glare, then scan the front and the back.',
  ];

  /// Reason the side looks like paper, or null.
  static String? rejection({
    required String side,
    required double aspectRatio,
    required double paperWhiteFraction,
    double? noteCoverage,
  }) {
    final pageShaped =
        aspectRatio >= minPageAspect && aspectRatio <= maxPageAspect;
    final white = (paperWhiteFraction * 100).round();

    if (pageShaped && paperWhiteFraction >= pageWhite) {
      return '$side: white paper border / printer paper around the note '
          '($white% blank paper, page-shaped ${aspectRatio.toStringAsFixed(2)} : 1)';
    }
    if (pageShaped && noteCoverage != null && noteCoverage < minNoteCoverage) {
      return '$side: the note fills only ${(noteCoverage * 100).round()}% '
          'of a sheet of paper (printed on paper)';
    }
    if (paperWhiteFraction >= blankWhite) {
      return '$side: mostly blank white paper ($white%)';
    }
    return null;
  }
}
