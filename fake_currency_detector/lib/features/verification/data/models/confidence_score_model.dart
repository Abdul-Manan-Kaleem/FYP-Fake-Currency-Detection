/// The authenticity score shown on the result gauge (0-100%).
///
/// Built by the rule engine (VerificationEngine) after all checks run.
/// Can be saved to / loaded from JSON (history).
library;

/// Which score range the percentage falls in (see [ConfidenceScoreModel.bandFor]).
/// `inconclusive` means no usable score (shown as 0).
enum ScoreBand { authentic, counterfeit, inconclusive }

/// Why the raw score was reduced, if it was.
/// - none: no penalty applied.
/// - criticalFailure: a core check (serial number or denomination) failed.
/// - featureFailure: some other feature check failed.
enum PenaltyType { none, criticalFailure, featureFailure }

/// The final confidence score plus how it was worked out.
class ConfidenceScoreModel {
  const ConfidenceScoreModel({
    required this.percentage,
    required this.rawScore,
    required this.band,
    this.penalty = PenaltyType.none,
    this.penaltyReason,
  });

  /// A "no score" value: 0%, inconclusive band, no penalty.
  const ConfidenceScoreModel.inconclusive()
      : percentage = 0,
        rawScore = 0,
        band = ScoreBand.inconclusive,
        penalty = PenaltyType.none,
        penaltyReason = null;

  /// Final, displayed authenticity confidence (0–100).
  final int percentage;

  /// Weighted sum of all feature scores before penalties (0–100).
  final double rawScore;

  /// Score range the final percentage belongs to.
  final ScoreBand band;

  /// Which penalty (if any) lowered the raw score.
  final PenaltyType penalty;

  /// Short text explaining the penalty. Null when there was no penalty.
  final String? penaltyReason;

  /// Verdict threshold mapping from the scoring spec.
  /// 85 and above = authentic, anything lower = counterfeit. There is no
  /// "suspicious" band: the result is either real or fake.
  static ScoreBand bandFor(int percentage) =>
      percentage >= 85 ? ScoreBand.authentic : ScoreBand.counterfeit;

  /// Rebuilds the score from saved JSON.
  factory ConfidenceScoreModel.fromJson(Map<String, dynamic> json) =>
      ConfidenceScoreModel(
        percentage: (json['percentage'] as num).toInt(),
        rawScore: (json['raw_score'] as num).toDouble(),
        // Enums are saved by name, so read them back by name.
        band: ScoreBand.values.byName(json['band'] as String),
        // Older saved data may have no penalty field, so default to 'none'.
        penalty: PenaltyType.values.byName(json['penalty'] as String? ?? 'none'),
        penaltyReason: json['penalty_reason'] as String?,
      );

  /// Converts the score to JSON (enums are stored by name).
  Map<String, dynamic> toJson() => {
        'percentage': percentage,
        'raw_score': rawScore,
        'band': band.name,
        'penalty': penalty.name,
        'penalty_reason': penaltyReason,
      };
}
