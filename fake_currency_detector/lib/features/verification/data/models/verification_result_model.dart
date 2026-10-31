import 'confidence_score_model.dart';
import 'feature_check_model.dart';
import 'note_analysis_model.dart';

/// App outcomes. The conclusive ones are PASSED APP CHECKS, SUSPICIOUS and
/// UNABLE TO VERIFY; INCOMPLETE and INVALID OBJECT are capture-flow states.
enum VerificationVerdict {
  /// Passed every check the app ran. Not a certified authentication.
  real,
  suspicious,

  /// Photocopy / printout on paper: shown as "Jaali Note / Fake Note".
  fake,
  unableToVerify,
  incomplete,
  notBanknote;

  String get label => switch (this) {
        real => 'PASSED APP CHECKS',
        suspicious => 'SUSPICIOUS',
        fake => 'JAALI NOTE / FAKE NOTE',
        unableToVerify => 'UNABLE TO VERIFY',
        incomplete => 'INCOMPLETE',
        notBanknote => 'INVALID OBJECT DETECTED',
      };

  String get shortLabel => switch (this) {
        real => 'PASSED APP CHECKS',
        suspicious => 'SUSPICIOUS',
        fake => 'FAKE',
        unableToVerify => 'UNABLE TO VERIFY',
        incomplete => 'INCOMPLETE',
        notBanknote => 'NOT A BANKNOTE',
      };

  /// Word shown under the gauge percentage.
  String get gaugeCaption => switch (this) {
        real => 'PASSED',
        suspicious => 'SUSPICIOUS',
        fake => 'FAKE',
        unableToVerify || incomplete || notBanknote => 'INCONCLUSIVE',
      };

  bool get isConclusive => this == real || this == suspicious || this == fake;
}

class VerificationResultModel {
  const VerificationResultModel({
    required this.verdict,
    required this.confidence,
    required this.checks,
    required this.messages,
    required this.analyzedAt,
    this.denomination,
    this.analysis,
    this.source = 'on-device',
  });

  final VerificationVerdict verdict;
  final ConfidenceScoreModel confidence;
  final List<FeatureCheckModel> checks;

  /// Human-readable reasons behind the verdict, most important first.
  final List<String> messages;
  final DateTime analyzedAt;
  final int? denomination;
  final NoteAnalysisModel? analysis;
  final String source;

  bool get isBanknote => verdict != VerificationVerdict.notBanknote;

  int get passedCount => checks.where((c) => c.passed).length;

  /// Checks that apply to this note (excludes N/A, e.g. thread on Rs 50).
  int get applicableCount =>
      checks.where((c) => c.status != CheckStatus.notApplicable).length;

  factory VerificationResultModel.fromJson(Map<String, dynamic> json) =>
      VerificationResultModel(
        verdict: VerificationVerdict.values.byName(json['verdict'] as String),
        confidence: ConfidenceScoreModel.fromJson(
            (json['confidence'] as Map).cast<String, dynamic>()),
        checks: [
          for (final c in json['checks'] as List)
            FeatureCheckModel.fromJson((c as Map).cast<String, dynamic>()),
        ],
        messages: List<String>.from(json['messages'] as List? ?? const []),
        analyzedAt: DateTime.parse(json['analyzed_at'] as String),
        denomination: json['denomination'] as int?,
        analysis: json['analysis'] is Map
            ? NoteAnalysisModel.fromJson(
                (json['analysis'] as Map).cast<String, dynamic>())
            : null,
        source: json['source'] as String? ?? 'api',
      );

  Map<String, dynamic> toJson() => {
        'verdict': verdict.name,
        'is_banknote': isBanknote,
        'confidence': confidence.toJson(),
        'checks': checks.map((c) => c.toJson()).toList(),
        'messages': messages,
        'analyzed_at': analyzedAt.toIso8601String(),
        'denomination': denomination,
        'analysis': analysis?.toJson(),
        'source': source,
      };
}
