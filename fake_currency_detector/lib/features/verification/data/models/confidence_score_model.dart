enum ScoreBand { authentic, suspicious, counterfeit, inconclusive }

enum PenaltyType { none, criticalFailure, featureFailure }

class ConfidenceScoreModel {
  const ConfidenceScoreModel({
    required this.percentage,
    required this.rawScore,
    required this.band,
    this.penalty = PenaltyType.none,
    this.penaltyReason,
  });

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

  final ScoreBand band;
  final PenaltyType penalty;
  final String? penaltyReason;

  /// Verdict threshold mapping from the scoring spec.
  static ScoreBand bandFor(int percentage) {
    if (percentage >= 85) return ScoreBand.authentic;
    if (percentage >= 40) return ScoreBand.suspicious;
    return ScoreBand.counterfeit;
  }

  factory ConfidenceScoreModel.fromJson(Map<String, dynamic> json) =>
      ConfidenceScoreModel(
        percentage: (json['percentage'] as num).toInt(),
        rawScore: (json['raw_score'] as num).toDouble(),
        band: ScoreBand.values.byName(json['band'] as String),
        penalty: PenaltyType.values.byName(json['penalty'] as String? ?? 'none'),
        penaltyReason: json['penalty_reason'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'percentage': percentage,
        'raw_score': rawScore,
        'band': band.name,
        'penalty': penalty.name,
        'penalty_reason': penaltyReason,
      };
}
