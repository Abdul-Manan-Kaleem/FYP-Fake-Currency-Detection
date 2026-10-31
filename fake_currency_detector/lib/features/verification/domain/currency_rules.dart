/// Pakistani currency verification rules (see CURRENCY_RULES).
enum DenominationMark { none, lines, dots }

class DenominationSpec {
  const DenominationSpec(
    this.value, {
    this.lines = 0,
    this.dots = 0,
    this.hasThread = true,
  });

  final int value;
  final int lines;
  final int dots;

  /// Rs 10, 20 and 50 carry no security thread (confirmed by the project
  /// owner; this overrides the "every denomination" line in CURRENCY_RULES).
  final bool hasThread;

  DenominationMark get mark => dots > 0
      ? DenominationMark.dots
      : lines > 0
          ? DenominationMark.lines
          : DenominationMark.none;

  /// How many individual lines/dots the note carries.
  int get markCount => dots > 0 ? dots : lines;
}

abstract final class CurrencyRules {
  static const Map<int, DenominationSpec> denominations = {
    10: DenominationSpec(10, hasThread: false),
    20: DenominationSpec(20, lines: 1, hasThread: false),
    50: DenominationSpec(50, lines: 2, hasThread: false),
    100: DenominationSpec(100, lines: 3),
    500: DenominationSpec(500, dots: 1),
    1000: DenominationSpec(1000, dots: 2),
    5000: DenominationSpec(5000, dots: 3),
  };

  /// Notes that carry a thread have exactly one. Never 2 or 3.
  static const int securityThreads = 1;

  /// A class that never produced a box but still scored this high somewhere
  /// counts as "faintly seen": the check is unclear, not failed.
  static const double faintDetectionScore = 0.10;
  static const int frontSbpSeals = 1;
  static const int backSbpSeals = 3;
  static const int frontSerialRegions = 2;

  /// Detections below this confidence never silently count as confirmed.
  static const double minDetectionConfidence = 0.5;

  static const int earliestPrintedYear = 1947;

  /// Notes whose border microprint is checked. For now Rs 5,000 only, at the
  /// project owner's request (other notes are tested separately).
  static const Set<int> microprintDenominations = {5000};

  /// Repeats needed to count as microprint rather than one corner numeral.
  static const int microprintMinOccurrences = 3;

  static bool hasMicroprint(int? value) => microprintDenominations.contains(value);

  /// Monument printed on the back of each note.
  static const Map<int, String> monuments = {
    10: 'Bab-e-Khyber',
    20: 'Mohenjo-daro',
    50: 'K2',
    100: 'Ziarat Residency',
    500: 'Badshahi Mosque',
    1000: 'Islamia College Peshawar',
    5000: 'Faisal Mosque',
  };

  /// Monument predictions below this never fail a note.
  static const double monumentMinConfidence = 0.60;

  static bool isSupported(int? value) => denominations.containsKey(value);
}

/// Weighted contribution of each feature to the authenticity score.
abstract final class ScoreWeights {
  static const double denomination = 20;
  static const double serialNumber = 25;
  static const double sbpSeals = 15;
  static const double linesDots = 15;
  static const double securityThread = 10;
  static const double printedYear = 5;
  static const double surfaceAnomaly = 10;
  static const double counterfeitCnn = 10;
  static const double microprint = 5;

  /// Back-side monument. A confident mismatch also overrides the verdict to
  /// FAKE (see VerificationEngine).
  static const double monument = 20;

  /// Multiplier applied when a core requirement (serial or denomination)
  /// fails; the result is additionally capped below the 40% line.
  static const double criticalPenalty = 0.45;
  static const int criticalCap = 39;

  /// Multiplier applied per failed non-critical feature; the result is capped
  /// below the 85% "real" line.
  static const double featurePenalty = 0.7;
  static const int featureCap = 84;
}

String formatRupees(int value) {
  final s = value.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return 'Rs ${buf.toString()}';
}
