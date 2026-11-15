/// Quick check run right after each photo is taken.
///
/// It tells the capture screen which side was photographed, so mistakes (wrong
/// side, same side twice, a different note) are caught before the full check.
library;

/// Which side of a note an image shows.
enum DetectedSide { front, back, unknown }

/// Result of the check run right after each capture.
class SideCheck {
  const SideCheck({
    required this.side,
    this.noteDenomination,
    this.monumentDenomination,
    this.looksLikeNote = true,
  });

  /// Default answer when the side could not be worked out.
  static const unknown = SideCheck(side: DetectedSide.unknown);

  /// Side the image appears to show.
  final DetectedSide side;

  /// False when the image shows no banknote at all (no note class or no
  /// security feature found). Defaults to true so a failed check never blocks
  /// capture; the full analysis still decides later.
  final bool looksLikeNote;

  /// Denomination YOLO11s reads on this side (confident only).
  /// Null when not read confidently.
  final int? noteDenomination;

  /// Denomination whose back-side monument was recognised (≥ 0.60), if the
  /// monument model is installed. Null otherwise.
  final int? monumentDenomination;
}

/// Detects the side (and denomination) of a captured note right after
/// capture, so a back scanned in the FRONT step, the same side twice, or the
/// back of a different note is caught before analysis.
abstract interface class SideClassifier {
  /// Looks at the photo at [imagePath] and returns what side it shows.
  Future<SideCheck> checkSide(String imagePath);
}
