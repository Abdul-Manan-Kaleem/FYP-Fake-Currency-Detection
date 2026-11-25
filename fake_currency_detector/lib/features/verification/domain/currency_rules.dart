/// Fixed facts about Pakistani banknotes and the scoring numbers.
///
/// The rule engine (VerificationEngine) reads these tables to decide what a
/// genuine note of each value should show. Change numbers here, not there.
library;

/// Pakistani currency verification rules (see CURRENCY_RULES).
/// Which kind of mark a note carries next to its value: none, lines or dots.
enum DenominationMark { none, lines, dots }

/// MobileNetV3-Small genuine/fake classifier (Rs 10-1,000). Switched off for
/// now: it does not run and its row is not shown. Set to true to bring it back.
const bool kSmallCnnEnabled = false;

/// What a genuine note of one value must show.
class DenominationSpec {
  const DenominationSpec(
    this.value, {
    this.lines = 0,
    this.dots = 0,
    this.hasThread = true,
  });

  /// Note value in rupees (10, 20, ... 5000).
  final int value;

  /// Number of security lines on the note (0 = none).
  final int lines;

  /// Number of security dots on the note (0 = none).
  final int dots;

  /// Rs 10, 20 and 50 carry no security thread (confirmed by the project
  /// owner; this overrides the "every denomination" line in CURRENCY_RULES).
  final bool hasThread;

  /// Whether this note uses dots, lines or neither. Dots win if both are set.
  DenominationMark get mark => dots > 0
      ? DenominationMark.dots
      : lines > 0
          ? DenominationMark.lines
          : DenominationMark.none;

  /// How many individual lines/dots the note carries.
  int get markCount => dots > 0 ? dots : lines;
}

/// The rule tables: what each Pakistani note should show.
abstract final class CurrencyRules {
  /// Expected marks per note value.
  /// - Rs 10: no lines, no dots, no thread.
  /// - Rs 20: 1 line, no thread.
  /// - Rs 50: 2 lines, no thread.
  /// - Rs 100: 3 lines, with thread.
  /// - Rs 500: 1 dot, with thread.
  /// - Rs 1,000: 2 dots, with thread.
  /// - Rs 5,000: 3 dots, with thread.
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

  /// SBP seals expected on the front of a note.
  static const int frontSbpSeals = 1;

  /// SBP seals expected on the back of a note.
  static const int backSbpSeals = 3;

  /// Serial number areas expected on the front (the note prints two).
  static const int frontSerialRegions = 2;

  /// Detections below this confidence never silently count as confirmed.
  static const double minDetectionConfidence = 0.5;

  /// Earliest believable printed year (Pakistan's independence year). A year
  /// before this, or after the current year, fails the printed year check.
  static const int earliestPrintedYear = 1947;

  /// Notes whose border microprint is checked. For now Rs 5,000 only, at the
  /// project owner's request (other notes are tested separately).
  static const Set<int> microprintDenominations = {5000};

  /// Repeats needed to count as microprint rather than one corner numeral.
  static const int microprintMinOccurrences = 3;

  /// True when this note value has its microprint checked.
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

  /// Quaid-e-Azam portrait predictions below this never fail a note.
  static const double portraitMinConfidence = 0.60;

  /// True when this value is one of the seven supported notes.
  static bool isSupported(int? value) => denominations.containsKey(value);
}

/// Weighted contribution of each feature to the authenticity score.
/// Each number is the points the feature can earn (out of 100 in total).
abstract final class ScoreWeights {
  /// Note value read correctly.
  static const double denomination = 20;

  /// Two front serial numbers read and matching.
  static const double serialNumber = 25;

  /// SBP seals found in the right numbers.
  static const double sbpSeals = 15;

  /// Correct security lines / dots for this note value.
  static const double linesDots = 15;

  /// Security thread present (where the note should have one).
  static const double securityThread = 10;

  /// A valid printed year.
  static const double printedYear = 5;

  /// Surface looks consistent (no strong anomaly).
  static const double surfaceAnomaly = 10;

  /// Rs 5,000 genuine/counterfeit classifier says genuine.
  static const double counterfeitCnn = 10;

  /// MobileNetV3-Small genuine/fake check for Rs 10–1,000 (the Rs 5,000
  /// notes use [counterfeitCnn] instead, so the two never both count).
  static const double smallCnn = 10;
  // (see kSmallCnnEnabled above)

  /// Border microprint repeats the right value.
  static const double microprint = 5;

  /// Back-side monument. A confident mismatch also overrides the verdict to
  /// FAKE (see VerificationEngine).
  static const double monument = 20;

  /// Front-side Quaid-e-Azam portrait. Like the monument, a confident
  /// mismatch overrides the verdict to FAKE (see VerificationEngine).
  static const double portrait = 10;

  /// Multiplier applied when a core requirement (serial or denomination)
  /// fails; the result is additionally capped below the 40% line.
  static const double criticalPenalty = 0.45;

  /// Highest percentage allowed after a critical failure (just under 40).
  static const int criticalCap = 39;

  /// Multiplier applied per failed non-critical feature; the result is capped
  /// below the 85% "real" line.
  static const double featurePenalty = 0.7;

  /// Highest percentage allowed after a feature failure (just under 85).
  static const int featureCap = 84;
}

/// Formats a rupee amount with thousands commas, e.g. 5000 -> "Rs 5,000".
String formatRupees(int value) {
  final s = value.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    // Put a comma before every group of three digits (counted from the end).
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return 'Rs ${buf.toString()}';
}
