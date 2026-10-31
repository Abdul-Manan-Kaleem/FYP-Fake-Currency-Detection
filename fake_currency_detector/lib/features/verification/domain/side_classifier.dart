/// Which side of a note an image shows.
enum DetectedSide { front, back, unknown }

/// Result of the check run right after each capture.
class SideCheck {
  const SideCheck({
    required this.side,
    this.noteDenomination,
    this.monumentDenomination,
  });

  static const unknown = SideCheck(side: DetectedSide.unknown);

  final DetectedSide side;

  /// Denomination YOLO11s reads on this side (confident only).
  final int? noteDenomination;

  /// Denomination whose back-side monument was recognised (≥ 0.60), if the
  /// monument model is installed.
  final int? monumentDenomination;
}

/// Detects the side (and denomination) of a captured note right after
/// capture, so a back scanned in the FRONT step, the same side twice, or the
/// back of a different note is caught before analysis.
abstract interface class SideClassifier {
  Future<SideCheck> checkSide(String imagePath);
}
