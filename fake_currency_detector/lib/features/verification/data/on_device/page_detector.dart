/// Page/printout detector. Kept in the project but currently unused.
///
/// In: image shape, share of blank-paper pixels and how much of the image
/// the note box covers. Out: a reason text if the side looks like paper,
/// otherwise null. No model: simple number checks only.
///
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
  /// Long/short side ratio range that looks like a sheet of paper.
  static const double minPageAspect = 1.25;
  static const double maxPageAspect = 1.50;

  /// Blank-paper share (0-1) that, on a page-shaped image, means paper.
  static const double pageWhite = 0.25;

  /// Blank-paper share (0-1) that means paper whatever the shape.
  static const double blankWhite = 0.45;

  /// A note box covering less than this share (0-1) of a page-shaped image
  /// means the note is printed on a sheet.
  static const double minNoteCoverage = 0.60;

  /// Advice lines shown to the user when a side is rejected.
  static const List<String> guidance = [
    'What to do:',
    '1. Use the real banknote, not a page, printout or photocopy.',
    '2. Put the note alone on a dark, plain surface (table or cloth).',
    '3. Fill the frame with the note so the scanner crops to its edges.',
    '4. Use even light without glare, then scan the front and the back.',
  ];

  /// Reason the side looks like paper, or null.
  ///
  /// [side] is a label for messages, [aspectRatio] is long/short edge,
  /// [paperWhiteFraction] is 0-1, [noteCoverage] is 0-1 (optional).
  static String? rejection({
    required String side,
    required double aspectRatio,
    required double paperWhiteFraction,
    double? noteCoverage,
  }) {
    // Step 1: is the image shaped like a sheet of paper?
    final pageShaped =
        aspectRatio >= minPageAspect && aspectRatio <= maxPageAspect;
    final white = (paperWhiteFraction * 100).round();

    // Step 2: page-shaped and lots of white = printer paper around a note.
    if (pageShaped && paperWhiteFraction >= pageWhite) {
      return '$side: white paper border / printer paper around the note '
          '($white% blank paper, page-shaped ${aspectRatio.toStringAsFixed(2)} : 1)';
    }
    // Step 3: page-shaped and the note fills little of it = printed page.
    if (pageShaped && noteCoverage != null && noteCoverage < minNoteCoverage) {
      return '$side: the note fills only ${(noteCoverage * 100).round()}% '
          'of a sheet of paper (printed on paper)';
    }
    // Step 4: mostly blank white, any shape.
    if (paperWhiteFraction >= blankWhite) {
      return '$side: mostly blank white paper ($white%)';
    }
    return null;
  }
}
