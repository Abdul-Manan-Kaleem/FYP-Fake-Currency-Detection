/// One saved scan: what the database stores and what the CSV export shows.
///
/// It is a flat copy of the interesting parts of a [VerificationResultModel]:
/// time, denomination, final verdict, confidence score and the status of each
/// security feature (including the Quaid-e-Azam portrait and the monument).
library;

import 'dart:convert';

import '../../verification/data/models/feature_check_model.dart';
import '../../verification/data/models/verification_result_model.dart';

/// The security features saved as one column each, in CSV / table order.
const List<FeatureCheckId> kRecordedFeatures = [
  FeatureCheckId.denomination,
  FeatureCheckId.serialNumber,
  FeatureCheckId.sbpSeals,
  FeatureCheckId.linesDots,
  FeatureCheckId.securityThread,
  FeatureCheckId.printedYear,
  FeatureCheckId.portrait,
  FeatureCheckId.monument,
  FeatureCheckId.surfaceAnomaly,
  FeatureCheckId.counterfeitCnn,
  FeatureCheckId.microprint,
];

/// Column / CSV name of one feature. The denomination CHECK is called
/// `denomination_check` so it never clashes with the `denomination` value
/// (the note value in rupees).
String columnOf(FeatureCheckId id) =>
    id == FeatureCheckId.denomination ? 'denomination_check' : id.name;

/// A saved scan result.
class ScanRecord {
  const ScanRecord({
    this.id,
    required this.scannedAt,
    required this.denomination,
    required this.verdict,
    required this.confidencePct,
    required this.rawScore,
    required this.penalty,
    required this.features,
    required this.summary,
    required this.detailsJson,
  });

  /// Database row number (null before the record is saved).
  final int? id;

  /// When the scan finished.
  final DateTime scannedAt;

  /// Note value in rupees, or null when it could not be read.
  final int? denomination;

  /// Final result: 'real', 'fake', 'unableToVerify', 'incomplete', ...
  final String verdict;

  /// The confidence percentage shown to the user (0-100).
  final int confidencePct;

  /// Score before penalties, 0-100 (earned weight / total weight).
  final double rawScore;

  /// Penalty applied: 'none', 'criticalFailure' or 'featureFailure'.
  final String penalty;

  /// Status of every recorded feature: feature name -> 'pass', 'fail',
  /// 'skipped', 'inconclusive', 'notApplicable', 'warning' or 'notRun'.
  final Map<String, String> features;

  /// Short text with the reasons (the result messages joined).
  final String summary;

  /// Full per-feature list (title, status, summary, points) as JSON text.
  final String detailsJson;

  /// Builds a record from a finished verification result.
  factory ScanRecord.fromResult(VerificationResultModel r) {
    final byId = {for (final c in r.checks) c.id: c};
    return ScanRecord(
      scannedAt: r.analyzedAt,
      denomination: r.denomination,
      verdict: r.verdict.name,
      confidencePct: r.confidence.percentage,
      rawScore: r.confidence.rawScore,
      penalty: r.confidence.penalty.name,
      features: {
        for (final id in kRecordedFeatures)
          id.name: byId[id]?.status.name ?? 'notRun',
      },
      summary: r.messages.join(' | '),
      detailsJson: jsonEncode([
        for (final c in r.checks)
          {
            'feature': c.id.name,
            'title': c.title,
            'status': c.status.name,
            'weight': c.weight,
            'earned': double.parse(c.earned.toStringAsFixed(2)),
            'summary': c.summary,
          },
      ]),
    );
  }

  /// Row for the database table.
  Map<String, Object?> toMap() => {
        'scanned_at': scannedAt.toIso8601String(),
        'denomination': denomination,
        'verdict': verdict,
        'confidence_pct': confidencePct,
        'raw_score': rawScore,
        'penalty': penalty,
        for (final id in kRecordedFeatures)
          columnOf(id): features[id.name] ?? 'notRun',
        'summary': summary,
        'details_json': detailsJson,
      };

  /// Reads a database row back.
  factory ScanRecord.fromMap(Map<String, Object?> m) => ScanRecord(
        id: m['id'] as int?,
        scannedAt: DateTime.parse(m['scanned_at'] as String),
        denomination: m['denomination'] as int?,
        verdict: m['verdict'] as String,
        confidencePct: m['confidence_pct'] as int,
        rawScore: (m['raw_score'] as num).toDouble(),
        penalty: m['penalty'] as String,
        features: {
          for (final id in kRecordedFeatures)
            id.name: (m[columnOf(id)] as String?) ?? 'notRun',
        },
        summary: (m['summary'] as String?) ?? '',
        detailsJson: (m['details_json'] as String?) ?? '[]',
      );
}
