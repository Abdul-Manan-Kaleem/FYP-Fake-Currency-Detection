enum FeatureCheckId {
  denomination,
  serialNumber,
  sbpSeals,
  linesDots,
  securityThread,
  printedYear,
  surfaceAnomaly,
  counterfeitCnn,
  microprint,
  monument,
}

/// `skipped`: could not run (missing model). `notApplicable`: this
/// denomination does not have the feature, so there is nothing to check.
/// `warning`: a finding from a not-yet-verified model; shown, but it does not
/// change the score or the verdict.
enum CheckStatus { pass, fail, inconclusive, skipped, notApplicable, warning }

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.firstWhere((e) => e.name == name, orElse: () => fallback);

/// One key/value row inside an expanded inspection tile.
class CheckDetailModel {
  const CheckDetailModel({required this.label, required this.value, this.ok});

  final String label;
  final String value;

  /// `null` when the row is informational only.
  final bool? ok;

  factory CheckDetailModel.fromJson(Map<String, dynamic> json) =>
      CheckDetailModel(
        label: json['label'] as String,
        value: json['value'] as String,
        ok: json['ok'] as bool?,
      );

  Map<String, dynamic> toJson() => {'label': label, 'value': value, 'ok': ok};
}

/// Character-by-character comparison of the two OCR'd serial numbers.
class SerialComparisonModel {
  const SerialComparisonModel({required this.first, required this.second});

  final String first;
  final String second;

  bool get lengthMatches => first.length == second.length;
  bool get matches => first == second;

  /// Index-aligned pairs; a missing character is represented by `null`.
  List<(String?, String?)> get pairs {
    final n = first.length > second.length ? first.length : second.length;
    return [
      for (var i = 0; i < n; i++)
        (
          i < first.length ? first[i] : null,
          i < second.length ? second[i] : null,
        ),
    ];
  }

  int get mismatchCount => pairs.where((p) => p.$1 != p.$2).length;

  factory SerialComparisonModel.fromJson(Map<String, dynamic> json) =>
      SerialComparisonModel(
        first: json['first'] as String,
        second: json['second'] as String,
      );

  Map<String, dynamic> toJson() => {
        'first': first,
        'second': second,
        'matches': matches,
        'mismatch_count': mismatchCount,
      };
}

class FeatureCheckModel {
  const FeatureCheckModel({
    required this.id,
    required this.title,
    required this.status,
    required this.weight,
    required this.earned,
    required this.summary,
    this.isCritical = false,
    this.details = const [],
    this.serialComparison,
  });

  final FeatureCheckId id;
  final String title;
  final CheckStatus status;

  /// Share of the total score (percentage points, all weights sum to 100).
  final double weight;

  /// Points earned out of [weight].
  final double earned;

  final String summary;
  final bool isCritical;
  final List<CheckDetailModel> details;
  final SerialComparisonModel? serialComparison;

  bool get passed => status == CheckStatus.pass;
  bool get failed => status == CheckStatus.fail;

  factory FeatureCheckModel.fromJson(Map<String, dynamic> json) =>
      FeatureCheckModel(
        id: _enumByName(
            FeatureCheckId.values, json['id'], FeatureCheckId.denomination),
        title: json['title'] as String,
        status: _enumByName(
            CheckStatus.values, json['status'], CheckStatus.inconclusive),
        weight: (json['weight'] as num).toDouble(),
        earned: (json['earned'] as num).toDouble(),
        summary: json['summary'] as String,
        isCritical: json['is_critical'] == true,
        details: [
          for (final d in (json['details'] as List? ?? const []))
            CheckDetailModel.fromJson((d as Map).cast<String, dynamic>()),
        ],
        serialComparison: json['serial_comparison'] is Map
            ? SerialComparisonModel.fromJson(
                (json['serial_comparison'] as Map).cast<String, dynamic>())
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id.name,
        'title': title,
        'status': status.name,
        'weight': weight,
        'earned': earned,
        'summary': summary,
        'is_critical': isCritical,
        'details': details.map((d) => d.toJson()).toList(),
        'serial_comparison': serialComparison?.toJson(),
      };
}
