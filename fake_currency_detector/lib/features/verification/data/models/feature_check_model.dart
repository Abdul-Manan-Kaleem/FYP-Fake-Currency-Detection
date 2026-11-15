/// One row of the result: a single security check and how it went.
///
/// Built by the rule engine (VerificationEngine) and shown as an inspection
/// tile on the result screen. Can be saved to / loaded from JSON (history).
library;

/// Which security check a [FeatureCheckModel] is about.
enum FeatureCheckId {
  /// Note value read by the detector (10, 20 ... 5000).
  denomination,

  /// Serial numbers on the front, compared with each other.
  serialNumber,

  /// State Bank of Pakistan seals.
  sbpSeals,

  /// Security lines or dots (depends on the denomination).
  linesDots,

  /// Security thread (not on Rs 10, 20, 50).
  securityThread,

  /// Year printed on the note.
  printedYear,

  /// Surface anomaly score from the MobileNetV3 model.
  surfaceAnomaly,

  /// Rs 5,000 genuine/counterfeit MobileNetV3-Large model.
  counterfeitCnn,

  /// Genuine/fake MobileNetV3-Small model for Rs 10-1,000.
  smallCnn,

  /// Tiny repeated text along the note border.
  microprint,

  /// Monument picture on the back of the note.
  monument,
}

/// `skipped`: could not run (missing model). `notApplicable`: this
/// denomination does not have the feature, so there is nothing to check.
/// `warning`: a finding from a not-yet-verified model; shown, but it does not
/// change the score or the verdict.
/// `pass` / `fail`: the check ran and gave a clear answer.
/// `inconclusive`: the check ran but the result was unclear.
enum CheckStatus { pass, fail, inconclusive, skipped, notApplicable, warning }

/// Finds an enum value by its name. Returns [fallback] if the name is unknown,
/// so old or odd saved data does not crash the app.
T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.firstWhere((e) => e.name == name, orElse: () => fallback);

/// One key/value row inside an expanded inspection tile.
class CheckDetailModel {
  const CheckDetailModel({required this.label, required this.value, this.ok});

  /// Left-hand text of the row (for example "Seals found").
  final String label;

  /// Right-hand text of the row.
  final String value;

  /// `null` when the row is informational only.
  final bool? ok;

  /// Rebuilds a detail row from saved JSON.
  factory CheckDetailModel.fromJson(Map<String, dynamic> json) =>
      CheckDetailModel(
        label: json['label'] as String,
        value: json['value'] as String,
        ok: json['ok'] as bool?,
      );

  /// Converts the row to JSON.
  Map<String, dynamic> toJson() => {'label': label, 'value': value, 'ok': ok};
}

/// Character-by-character comparison of the two OCR'd serial numbers.
class SerialComparisonModel {
  const SerialComparisonModel({required this.first, required this.second});

  /// Text read for the first serial number.
  final String first;

  /// Text read for the second serial number.
  final String second;

  /// True when both serials have the same number of characters.
  bool get lengthMatches => first.length == second.length;

  /// True when both serials are exactly the same text.
  bool get matches => first == second;

  /// Index-aligned pairs; a missing character is represented by `null`.
  List<(String?, String?)> get pairs {
    // Go up to the length of the longer serial.
    final n = first.length > second.length ? first.length : second.length;
    return [
      for (var i = 0; i < n; i++)
        (
          i < first.length ? first[i] : null,
          i < second.length ? second[i] : null,
        ),
    ];
  }

  /// How many positions differ (a missing character counts as different).
  int get mismatchCount => pairs.where((p) => p.$1 != p.$2).length;

  /// Rebuilds the comparison from saved JSON.
  factory SerialComparisonModel.fromJson(Map<String, dynamic> json) =>
      SerialComparisonModel(
        first: json['first'] as String,
        second: json['second'] as String,
      );

  /// Converts to JSON. 'matches' and 'mismatch_count' are saved for reading
  /// only; fromJson works them out again from first and second.
  Map<String, dynamic> toJson() => {
        'first': first,
        'second': second,
        'matches': matches,
        'mismatch_count': mismatchCount,
      };
}

/// The outcome of one security check, with its score and explanation.
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

  /// Which check this is.
  final FeatureCheckId id;

  /// Name shown on the tile.
  final String title;

  /// Pass, fail, unclear, etc.
  final CheckStatus status;

  /// Share of the total score (percentage points, all weights sum to 100).
  final double weight;

  /// Points earned out of [weight].
  final double earned;

  /// One-line explanation shown under the title.
  final String summary;

  /// True for core checks (serial or denomination). A failure here lowers the
  /// score much more.
  final bool isCritical;

  /// Extra rows shown when the tile is expanded.
  final List<CheckDetailModel> details;

  /// Only set for the serial number check. Null for all other checks.
  final SerialComparisonModel? serialComparison;

  /// True when the check passed.
  bool get passed => status == CheckStatus.pass;

  /// True when the check clearly failed.
  bool get failed => status == CheckStatus.fail;

  /// Rebuilds a check from saved JSON.
  factory FeatureCheckModel.fromJson(Map<String, dynamic> json) =>
      FeatureCheckModel(
        // Unknown names fall back to a safe default instead of crashing.
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
        // Only the serial check has a comparison.
        serialComparison: json['serial_comparison'] is Map
            ? SerialComparisonModel.fromJson(
                (json['serial_comparison'] as Map).cast<String, dynamic>())
            : null,
      );

  /// Converts the check to JSON (enums are stored by name).
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
