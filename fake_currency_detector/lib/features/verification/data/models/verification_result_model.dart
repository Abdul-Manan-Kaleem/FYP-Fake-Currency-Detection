/// The final result of one banknote check, shown on the result screen.
///
/// Created by the rule engine (VerificationEngine) from the raw detector
/// output ([NoteAnalysisModel]). Can be saved to / loaded from JSON (history).
library;

import 'confidence_score_model.dart';
import 'feature_check_model.dart';
import 'note_analysis_model.dart';

/// App outcomes. The verdict is binary: REAL or FAKE. The other states are
/// not verdicts: UNABLE TO VERIFY asks for a better photo, INCOMPLETE means a
/// side is missing, and NOT A BANKNOTE means the image is not a note.
enum VerificationVerdict {
  /// Passed every check the app ran. Not a certified authentication.
  real,

  /// Failed at least one check (a missing security feature, wrong or
  /// patterned serial number, wrong monument, photocopy, ...).
  fake,

  /// The app could not run enough checks to decide; the user should retake
  /// the photos. This is NOT a fake verdict.
  unableToVerify,

  /// One or both sides of the note were not captured.
  incomplete,

  /// The image does not show a banknote.
  notBanknote;

  /// Full text shown on the result screen.
  String get label => switch (this) {
        real => 'REAL NOTE',
        fake => 'FAKE NOTE',
        unableToVerify => 'UNABLE TO VERIFY',
        incomplete => 'INCOMPLETE',
        notBanknote => 'INVALID OBJECT DETECTED',
      };

  /// Shorter text for small spaces (for example history list).
  String get shortLabel => switch (this) {
        real => 'REAL',
        fake => 'FAKE',
        unableToVerify => 'UNABLE TO VERIFY',
        incomplete => 'INCOMPLETE',
        notBanknote => 'NOT A BANKNOTE',
      };

  /// Word shown under the gauge percentage.
  String get gaugeCaption => switch (this) {
        real => 'REAL',
        fake => 'FAKE',
        unableToVerify || incomplete || notBanknote => 'INCONCLUSIVE',
      };

  /// True when the app reached a decision (real or fake).
  bool get isConclusive => this == real || this == fake;
}

/// Everything about one finished check: verdict, score, each feature check
/// and the reasons shown to the user.
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

  /// The final outcome.
  final VerificationVerdict verdict;

  /// The 0-100 score and how it was built.
  final ConfidenceScoreModel confidence;

  /// One entry per feature check (serial number, seals, thread, ...).
  final List<FeatureCheckModel> checks;

  /// Human-readable reasons behind the verdict, most important first.
  final List<String> messages;

  /// When the check was done.
  final DateTime analyzedAt;

  /// Note value in rupees (for example 500). Null if it could not be read.
  final int? denomination;

  /// The raw detector output this result was built from. Can be null.
  final NoteAnalysisModel? analysis;

  /// Where the analysis ran: 'on-device' (the phone) or 'api'.
  final String source;

  /// False only when the image was not a banknote at all.
  bool get isBanknote => verdict != VerificationVerdict.notBanknote;

  /// How many checks passed.
  int get passedCount => checks.where((c) => c.passed).length;

  /// Checks that apply to this note (excludes N/A, e.g. thread on Rs 50).
  int get applicableCount =>
      checks.where((c) => c.status != CheckStatus.notApplicable).length;

  /// Rebuilds a result from saved JSON.
  factory VerificationResultModel.fromJson(Map<String, dynamic> json) =>
      VerificationResultModel(
        // The verdict is saved by its enum name.
        verdict: VerificationVerdict.values.byName(json['verdict'] as String),
        confidence: ConfidenceScoreModel.fromJson(
            (json['confidence'] as Map).cast<String, dynamic>()),
        // Rebuild each saved check one by one.
        checks: [
          for (final c in json['checks'] as List)
            FeatureCheckModel.fromJson((c as Map).cast<String, dynamic>()),
        ],
        messages: List<String>.from(json['messages'] as List? ?? const []),
        analyzedAt: DateTime.parse(json['analyzed_at'] as String),
        denomination: json['denomination'] as int?,
        // The raw analysis is optional, so keep null if it was not saved.
        analysis: json['analysis'] is Map
            ? NoteAnalysisModel.fromJson(
                (json['analysis'] as Map).cast<String, dynamic>())
            : null,
        source: json['source'] as String? ?? 'api',
      );

  /// Converts the result to JSON. Dates are stored as ISO-8601 text.
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
