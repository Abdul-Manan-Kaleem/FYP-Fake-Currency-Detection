import 'dart:math' as math;

import '../data/models/confidence_score_model.dart';
import '../data/models/feature_check_model.dart';
import '../data/models/note_analysis_model.dart';
import '../data/models/verification_result_model.dart';
import 'currency_rules.dart';

/// VERIFICATION ENGINE  (the "judge" of the app)
///
/// PURPOSE
/// The scanning pipeline (see on_device_currency_verification_repository.dart)
/// collects raw EVIDENCE from the photos: detected boxes, OCR text, classifier
/// scores. This file does not look at images. It takes that evidence
/// (a [NoteAnalysisModel]) and decides what it means:
///   * one list of feature checks (pass / fail / inconclusive / ...),
///   * one weighted authenticity score from 0 to 100,
///   * one final result state: PASSED APP CHECKS, SUSPICIOUS,
///     UNABLE TO VERIFY, FAKE, INCOMPLETE or NOT A BANKNOTE.
///
/// The rule tables (denominations, thresholds, score weights) live in
/// currency_rules.dart. This file only applies them.
///
/// It is pure and synchronous (no Flutter, no I/O), so it is easy to unit
/// test. The clock can be injected for tests.
///
/// WHERE IT FITS IN THE PIPELINE
///   camera photos -> repository (YOLO11s, OCR, classifiers) -> evidence
///   -> VerificationEngine.evaluate() -> VerificationResultModel -> UI.
///
/// MAIN SECTIONS (search for these names)
///  1. Class setup: clock, minimum confidence, _passFactor.
///  2. incomplete() and rejected(): early results without full evidence.
///  3. evaluate(): the main flow.
///     a. Early exits (photocopy, not a banknote, missing side, bad photo).
///     b. Build the list of checks.
///     c. Add up the weighted score.
///     d. Apply penalties and caps, then choose the result state.
///     e. Write the messages the user reads.
///  4. Helpers: _unable, _agreedDenomination, _rs, _check.
///  5. One private method per check, in this order:
///     denomination, serial numbers, SBP seals, lines/dots, security thread,
///     printed year, alteration CNN (Rs 5,000), genuine/counterfeit CNN
///     (Rs 5,000), small CNN (switched off), microprint, monument.
///
/// STATUS WORDS USED BY EVERY CHECK
///  * pass          : evidence matches the rule. Earns score.
///  * fail          : evidence clearly breaks the rule. Earns nothing and
///                    triggers a penalty.
///  * inconclusive  : the evidence is too unclear to judge (blur, low
///                    confidence). Never counted as fake; leads to
///                    UNABLE TO VERIFY unless something else clearly failed.
///  * skipped       : the check did not run (model missing, not readable).
///                    It is left out of the score.
///  * notApplicable : the rule does not apply to this note (for example no
///                    thread on Rs 10/20/50). Left out of the score.
///  * warning       : only the monument check uses it (preliminary model).
///                    Reported, but left out of the score.
class VerificationEngine {
  /// [_clock] lets tests fix "now". When null the real current time is used.
  const VerificationEngine({this._clock});

  /// Optional fake clock for tests.
  final DateTime Function()? _clock;

  /// Current time, used for the result timestamp and for the "printed year
  /// must not be in the future" rule.
  DateTime get _now => (_clock ?? DateTime.now)();

  /// Lowest detection confidence (0.5) that may count as "confirmed".
  /// Anything below it is treated as unclear, never as a clean pass.
  static const double _minConf = CurrencyRules.minDetectionConfidence;

  /// Score earned by a passing feature: 85% of its weight at the minimum
  /// accepted confidence, rising to 100% at full confidence. This guarantees
  /// that a note passing every check always lands in the "real" band
  /// (85 and above, see ConfidenceScoreModel.bandFor).
  ///
  /// Example: confidence 0.5 -> factor 0.85; confidence 1.0 -> factor 1.0.
  static double _passFactor(double confidence) {
    final normalised =
        ((confidence - _minConf) / (1 - _minConf)).clamp(0.0, 1.0);
    return 0.85 + 0.15 * normalised;
  }

  /// Result state INCOMPLETE: only one side of the note was captured.
  /// Input: [hasFront] true if the front exists (so the back is missing).
  /// Output: a result with no checks and no score. A single side can never
  /// be called real, so the app asks for both sides.
  VerificationResultModel incomplete({required bool hasFront}) {
    return VerificationResultModel(
      verdict: VerificationVerdict.incomplete,
      confidence: const ConfidenceScoreModel.inconclusive(),
      checks: const [],
      messages: [
        hasFront
            ? 'Only the FRONT side was captured. Both sides are mandatory.'
            : 'Only the BACK side was captured. Both sides are mandatory.',
        'A single-side scan can never be declared real. Capture both sides '
            'and analyze again.',
      ],
      analyzedAt: _now,
      source: 'client',
    );
  }

  /// Result state NOT A BANKNOTE for images rejected by the on-device
  /// banknote gate, before any feature check ran.
  /// Input: [reasons] are the gate's plain-text reasons, shown to the user.
  /// Output: a result with no checks and no score.
  VerificationResultModel rejected(List<String> reasons) {
    return VerificationResultModel(
      verdict: VerificationVerdict.notBanknote,
      confidence: const ConfidenceScoreModel.inconclusive(),
      checks: const [],
      messages: [
        'The captured image is not recognized as a Pakistani currency note.',
        ...reasons,
      ],
      analyzedAt: _now,
      source: 'device',
    );
  }

  /// MAIN ENTRY POINT. Turns the pipeline evidence into the final result.
  ///
  /// Input: [analysis] (evidence for the front and back, plus classifier
  /// outputs) and [source] (a label such as 'device' or 'api' stored on the
  /// result).
  /// Output: a [VerificationResultModel] with the result state, score,
  /// list of checks and user messages.
  ///
  /// Steps:
  ///  1. Early exits: photocopy -> FAKE, not a banknote, missing side,
  ///     poor image quality -> UNABLE TO VERIFY.
  ///  2. Run every check and collect the list.
  ///  3. Score = earned weight / total weight of the checks that ran.
  ///  4. If nothing failed but something was unclear -> UNABLE TO VERIFY.
  ///  5. Apply penalties and caps for failures.
  ///  6. Pick the result state from the score band (monument can force FAKE).
  ///  7. Build the messages and return.
  VerificationResultModel evaluate(
    NoteAnalysisModel analysis, {
    String source = 'api',
  }) {
    // ---- Early exit: photocopy ----
    // Note printed on paper (photocopy / printout): FAKE for every
    // denomination, without running the feature checks.
    if (analysis.rejectionKind == 'photocopy') {
      return VerificationResultModel(
        verdict: VerificationVerdict.fake,
        confidence: const ConfidenceScoreModel(
          percentage: 0,
          rawScore: 0,
          band: ScoreBand.counterfeit,
          penalty: PenaltyType.criticalFailure,
          penaltyReason: 'Photocopy / printed paper detected',
        ),
        checks: const [],
        messages: [
          'Fake note: this looks like a photocopy or printout on paper, not a '
              'real note.',
          ...analysis.rejectionReasons,
        ],
        analyzedAt: _now,
        analysis: analysis,
        source: source,
      );
    }

    // ---- Early exit: not a banknote ----
    // The gate in the repository decided the image is not a Pakistani note.
    if (!analysis.isBanknote) {
      return VerificationResultModel(
        verdict: VerificationVerdict.notBanknote,
        confidence: const ConfidenceScoreModel.inconclusive(),
        checks: const [],
        messages: [
          'The captured image is not recognized as a Pakistani currency note.',
          ...analysis.rejectionReasons,
        ],
        analyzedAt: _now,
        analysis: analysis,
        source: source,
      );
    }

    // ---- Early exit: a side is missing ----
    final front = analysis.front;
    final back = analysis.back;
    if (front == null || back == null) {
      return _unable(
        analysis,
        source,
        ['The detector did not return results for both sides.'],
      );
    }

    // ---- Early exit: image quality ----
    // Image-quality gate: never call a note fake because of a poor photo.
    final qualityIssues = [
      for (final i in front.quality.issues) 'FRONT: $i',
      for (final i in back.quality.issues) 'BACK: $i',
    ];
    if (qualityIssues.isNotEmpty) {
      return _unable(analysis, source, [
        ...qualityIssues,
        'Image quality prevents reliable inspection of the security features.',
      ]);
    }

    // ---- Step 2: run every check ----
    // The denomination check is kept in its own variable because the
    // lines/dots check needs to know if the denomination was unclear.
    final denominationCheck = _denomination(front, back);
    final checks = <FeatureCheckModel>[
      denominationCheck,
      _serialNumbers(front),
      _sbpSeals(front, back),
      _linesDots(front, denominationCheck),
      _thread(front, back),
      _printedYear(front),
      _surface(analysis.anomaly, analysis.anomalySkipReason,
          analysis.rs5000OnlyReason),
      _counterfeitCnn(analysis.counterfeitCnn, analysis.rs5000OnlyReason),
      // Rs 10–1,000 only; Rs 5,000 has its own two classifiers above, so it
      // gets no row for this one.
      // Switched off for now (kSmallCnnEnabled): the row disappears too.
      if (kSmallCnnEnabled &&
          (_agreedDenomination(front, back) ?? front.denomination) != 5000)
        _smallCnn(
          analysis.smallCnn,
          analysis.smallCnnSkipReason,
          _agreedDenomination(front, back) ?? front.denomination,
        ),
      // Microprint is only checked on Rs 5,000 for now; other notes get no
      // microprint row at all.
      if (CurrencyRules.hasMicroprint(front.denomination))
        _microprint(analysis.microprint, front.denomination),
      _monument(
        analysis.monument,
        _agreedDenomination(front, back) ?? front.denomination,
      ),
      // Quaid-e-Azam portrait on the front, checked the same way as the
      // monument on the back.
      _portrait(
        analysis.portrait,
        _agreedDenomination(front, back) ?? front.denomination,
      ),
    ];

    // ---- Step 3: weighted score ----
    // Only checks that really ran count. Skipped, not-applicable and
    // warning checks are removed from BOTH the earned and the total weight,
    // so a check that could not run never helps or hurts the percentage.
    // Inconclusive checks stay in the total but earn 0.
    final scored = checks.where((c) =>
        c.status != CheckStatus.skipped &&
        c.status != CheckStatus.notApplicable &&
        c.status != CheckStatus.warning);
    final totalWeight = scored.fold<double>(0, (s, c) => s + c.weight);
    final earned = scored.fold<double>(0, (s, c) => s + c.earned);
    // Raw score = earned / total * 100 (before any penalty).
    final raw = totalWeight == 0 ? 0.0 : earned / totalWeight * 100;

    final failures = checks.where((c) => c.failed).toList();
    final critical = failures.where((c) => c.isCritical).toList();
    final inconclusive =
        checks.where((c) => c.status == CheckStatus.inconclusive).toList();

    // ---- Step 4: unclear evidence -> UNABLE TO VERIFY ----
    // A clear failure wins; otherwise anything unreadable means retake.
    if (failures.isEmpty && inconclusive.isNotEmpty) {
      return _unable(
        analysis,
        source,
        [
          for (final c in inconclusive) '${c.title}: ${c.summary}',
          'Some features could not be inspected reliably. '
              'This does not mean the note is fake.',
        ],
        checks: checks,
        denomination: _agreedDenomination(front, back),
      );
    }

    // ---- Step 5: penalties and caps ----
    // pct = final percentage shown to the user.
    late final int pct;
    var penalty = PenaltyType.none;
    String? penaltyReason;

    if (critical.isNotEmpty) {
      // Critical failure (denomination or serial numbers, plus a wrong
      // monument). Score is cut to 45% and capped at 39, which is under the
      // 40 line, so it can never look like a "maybe" result.
      pct = math.min(
        (raw * ScoreWeights.criticalPenalty).round(),
        ScoreWeights.criticalCap,
      );
      penalty = PenaltyType.criticalFailure;
      penaltyReason =
          'Critical failure: ${critical.map((c) => c.title).join(', ')}';
    } else if (failures.isNotEmpty) {
      // Ordinary failures: the score is multiplied by 0.7 once for EACH
      // failed check, so more failures hurt more. The cap of 84 keeps the
      // score under the 85 "real" line, so a note with any failure can
      // never pass.
      pct = math.min(
        (raw * math.pow(ScoreWeights.featurePenalty, failures.length)).round(),
        ScoreWeights.featureCap,
      );
      penalty = PenaltyType.featureFailure;
      penaltyReason =
          'Failed requirement: ${failures.map((c) => c.title).join(', ')}';
    } else {
      // No failures: the raw score is used as it is.
      pct = raw.round();
    }

    // ---- Step 6: choose the result state ----
    // Band: 85 and above = authentic, anything lower = counterfeit.
    final band = ConfidenceScoreModel.bandFor(pct);
    // The verdict is binary: REAL or FAKE. There is no "suspicious" middle
    // result. Any failed check (a missing security feature, wrong serial
    // numbers, a patterned serial number, a wrong monument) means FAKE.
    // A confidently wrong back-side monument also means FAKE, even if every
    // other check passed.
    final monumentFailed = checks.any(
        (c) => c.id == FeatureCheckId.monument && c.status == CheckStatus.fail);
    // The same holds for a confidently wrong Quaid-e-Azam portrait on the front.
    final portraitFailed = checks.any(
        (c) => c.id == FeatureCheckId.portrait && c.status == CheckStatus.fail);
    final verdict = (monumentFailed ||
            portraitFailed ||
            failures.isNotEmpty ||
            band != ScoreBand.authentic)
        ? VerificationVerdict.fake
        : VerificationVerdict.real;
    final denom = _agreedDenomination(front, back) ?? front.denomination;

    // ---- Step 7: messages shown to the user ----
    // All messages are in English.
    final skipped =
        checks.where((c) => c.status == CheckStatus.skipped).toList();
    final messages = <String>[
      if (monumentFailed && denom != null)
        'Fake note: the monument on the back does not match. A Rs $denom '
            'note should show ${CurrencyRules.monuments[denom]}.',
      if (portraitFailed && denom != null)
        'Fake note: the Quaid-e-Azam portrait on the front does not match a '
            'Rs $denom note.',
      if (failures.isEmpty && skipped.isEmpty)
        analysis.rs5000OnlyReason == null
            ? 'All YOLO11s security features and OCR serial checks passed, '
                'and both Rs 5,000 CNNs found nothing wrong.'
            : analysis.smallCnn != null
                ? 'All YOLO11s security features and OCR serial checks passed, '
                    'and the genuine/fake CNN found nothing wrong.'
                : 'All YOLO11s security features and OCR serial checks passed.'
      else if (failures.isEmpty)
        'Every check that could run passed.'
      else
        for (final c in failures) '${c.title}: ${c.summary}',
      for (final c in inconclusive) '${c.title} could not be fully inspected.',
      if (skipped.isNotEmpty)
        'Not checked: ${skipped.map((c) => c.title).join(', ')}. The score '
            'covers only the checks that ran.',
      if (verdict == VerificationVerdict.real &&
          checks.any((c) =>
              c.id == FeatureCheckId.microprint &&
              c.status == CheckStatus.skipped))
        'Microprint could not be read, so the note was verified by its other '
            'features.',
      if (verdict == VerificationVerdict.real)
        'PASSED APP CHECKS means the note passed this application\'s '
            'programmed checks; it is not a certified authentication.',
    ];

    return VerificationResultModel(
      verdict: verdict,
      confidence: ConfidenceScoreModel(
        percentage: pct.clamp(0, 100),
        rawScore: double.parse(raw.toStringAsFixed(2)),
        band: band,
        penalty: penalty,
        penaltyReason: penaltyReason,
      ),
      checks: checks,
      messages: messages,
      analyzedAt: _now,
      denomination: _agreedDenomination(front, back) ?? front.denomination,
      analysis: analysis,
      source: source,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Result state UNABLE TO VERIFY: the evidence was too unclear to judge.
  /// This is NOT a fake verdict; the user is asked to retake the photos.
  /// Inputs: [messages] explain why; optional [checks] and [denomination]
  /// are kept so the screen can still show what was read.
  VerificationResultModel _unable(
    NoteAnalysisModel analysis,
    String source,
    List<String> messages, {
    List<FeatureCheckModel> checks = const [],
    int? denomination,
  }) {
    return VerificationResultModel(
      verdict: VerificationVerdict.unableToVerify,
      confidence: const ConfidenceScoreModel.inconclusive(),
      checks: checks,
      messages: messages,
      analyzedAt: _now,
      denomination: denomination,
      analysis: analysis,
      source: source,
    );
  }

  /// The denomination only if front and back both read the SAME value.
  /// Returns null if either side is unknown or they disagree.
  int? _agreedDenomination(SideDetectionModel f, SideDetectionModel b) =>
      f.denomination != null && f.denomination == b.denomination
          ? f.denomination
          : null;

  /// Formats a denomination for display, for example "Rs 5,000".
  /// Shows a dash when the value is unknown.
  String _rs(int? v) => v == null ? '—' : formatRupees(v);

  /// Builds one [FeatureCheckModel]. Every check goes through here.
  ///
  /// Score rule: only a PASS earns points. Earned = weight * _passFactor
  /// (confidence), so a more confident pass earns up to the full weight.
  /// Every other status earns 0. [critical] marks checks whose failure
  /// triggers the heavy penalty in evaluate(). [confidence] defaults to 1
  /// when the check has no confidence value of its own.
  FeatureCheckModel _check({
    required FeatureCheckId id,
    required String title,
    required double weight,
    required CheckStatus status,
    required String summary,
    double confidence = 1,
    bool critical = false,
    List<CheckDetailModel> details = const [],
    SerialComparisonModel? serial,
  }) {
    return FeatureCheckModel(
      id: id,
      title: title,
      status: status,
      weight: weight,
      earned: status == CheckStatus.pass ? weight * _passFactor(confidence) : 0,
      summary: summary,
      isCritical: critical,
      details: details,
      serialComparison: serial,
    );
  }

  // ---------------------------------------------------------------------------
  // ---- Check: denomination match ----
  // ---------------------------------------------------------------------------

  /// Check 1: the front and back must show the SAME supported denomination.
  /// Applies to all notes. Inputs: front and back detections from YOLO11s.
  ///  * inconclusive: a side has no denomination or its confidence is below
  ///    the minimum (0.5).
  ///  * pass: both sides agree and the value is a supported denomination.
  ///  * fail: unsupported value, or front and back differ.
  /// Weight 20. Critical, because a wrong or mixed denomination means the
  /// two sides may come from different notes.
  FeatureCheckModel _denomination(SideDetectionModel f, SideDetectionModel b) {
    final summary = 'Front: ${_rs(f.denomination)} | Back: ${_rs(b.denomination)}';
    final details = [
      CheckDetailModel(
        label: 'Front (YOLO11s)',
        value: '${_rs(f.denomination)} · ${_pct(f.denominationConfidence)}',
        ok: CurrencyRules.isSupported(f.denomination),
      ),
      CheckDetailModel(
        label: 'Back (YOLO11s)',
        value: '${_rs(b.denomination)} · ${_pct(b.denominationConfidence)}',
        ok: CurrencyRules.isSupported(b.denomination),
      ),
    ];

    final unreadable = f.denomination == null ||
        b.denomination == null ||
        f.denominationConfidence < _minConf ||
        b.denominationConfidence < _minConf;
    if (unreadable) {
      return _check(
        id: FeatureCheckId.denomination,
        title: 'Denomination Match',
        weight: ScoreWeights.denomination,
        status: CheckStatus.inconclusive,
        summary: 'Denomination could not be read reliably',
        critical: true,
        details: details,
      );
    }

    final ok = CurrencyRules.isSupported(f.denomination) &&
        f.denomination == b.denomination;
    return _check(
      id: FeatureCheckId.denomination,
      title: 'Denomination Match',
      weight: ScoreWeights.denomination,
      status: ok ? CheckStatus.pass : CheckStatus.fail,
      summary: ok
          ? summary
          : !CurrencyRules.isSupported(f.denomination)
              ? 'Unsupported denomination detected · $summary'
              : 'Front and back denominations differ · $summary',
      confidence: math.min(f.denominationConfidence, b.denominationConfidence),
      critical: true,
      details: details,
    );
  }

  // ---------------------------------------------------------------------------
  // ---- Check: serial numbers ----
  // ---------------------------------------------------------------------------

  /// Check 2: the front has two printed serial numbers and they must match
  /// each other exactly. Applies to all notes. Input: the front side's OCR
  /// reads of the two serial regions.
  ///  * fail: the number of serial regions found is not 2.
  ///  * inconclusive: a read is empty or below minimum confidence (retake).
  ///  * pass: both reads are equal after removing spaces and upper-casing.
  ///  * fail: lengths differ or any character differs.
  /// Weight 25, the biggest weight, because matching serials are the
  /// strongest single sign of a genuine note. Critical.
  FeatureCheckModel _serialNumbers(SideDetectionModel f) {
    const title = 'Serial Number OCR';
    final reads = f.serialNumbers;
    final details = [
      CheckDetailModel(
        label: 'Regions detected',
        value: '${reads.length}/${CurrencyRules.frontSerialRegions}',
        ok: reads.length == CurrencyRules.frontSerialRegions,
      ),
      for (var i = 0; i < reads.length; i++)
        CheckDetailModel(
          label: 'Serial #${i + 1}',
          value: '${reads[i].text.isEmpty ? '(unreadable)' : reads[i].text}'
              ' · ${_pct(reads[i].confidence)}',
        ),
      for (var i = 0; i < reads.length; i++)
        if (reads[i].ocrReads.isNotEmpty)
          CheckDetailModel(
            label: 'OCR passes #${i + 1}',
            value: reads[i].ocrReads.map((r) => r.isEmpty ? '∅' : r).join(' / '),
          ),
    ];

    // Step 1: wrong number of serial regions is a failure.
    if (reads.length != CurrencyRules.frontSerialRegions) {
      return _check(
        id: FeatureCheckId.serialNumber,
        title: title,
        weight: ScoreWeights.serialNumber,
        status: CheckStatus.fail,
        summary: 'Expected ${CurrencyRules.frontSerialRegions} serial-number '
            'regions, found ${reads.length}',
        critical: true,
        details: details,
      );
    }

    // Step 2: unreadable OCR is unclear, never a fail (could be glare).
    final unreadable =
        reads.any((r) => r.text.trim().isEmpty || r.confidence < _minConf);
    if (unreadable) {
      return _check(
        id: FeatureCheckId.serialNumber,
        title: title,
        weight: ScoreWeights.serialNumber,
        status: CheckStatus.inconclusive,
        summary: 'OCR could not read the serial numbers clearly · retake closer, '
            'without glare on the serials',
        critical: true,
        details: details,
      );
    }

    // Step 3: a real serial number looks random. A serial made of one repeated
    // digit (0000000, 1111111) or an obvious pattern (1234567, 7654321,
    // 1212121) is a fake. This is a critical failure and gives a FAKE result.
    for (final (i, r) in reads.indexed) {
      final pattern = serialPatternName(r.text);
      if (pattern != null) {
        return _check(
          id: FeatureCheckId.serialNumber,
          title: title,
          weight: ScoreWeights.serialNumber,
          status: CheckStatus.fail,
          summary: 'Serial number ${i + 1} ("${r.text.trim()}") is not random: '
              '$pattern',
          confidence: r.confidence,
          critical: true,
          details: details,
        );
      }
    }

    // Step 4: compare the two serials (ignoring case and spaces).
    String norm(String s) => s.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    final comparison = SerialComparisonModel(
      first: norm(reads[0].text),
      second: norm(reads[1].text),
    );
    final ok = comparison.matches;
    return _check(
      id: FeatureCheckId.serialNumber,
      title: title,
      weight: ScoreWeights.serialNumber,
      status: ok ? CheckStatus.pass : CheckStatus.fail,
      summary: ok
          ? 'Both serials match character-for-character'
          : !comparison.lengthMatches
              ? 'Serial lengths differ (${comparison.first.length} vs '
                  '${comparison.second.length})'
              : '${comparison.mismatchCount} character(s) differ',
      confidence: math.min(reads[0].confidence, reads[1].confidence),
      critical: true,
      details: details,
      serial: comparison,
    );
  }

  /// Tells whether a serial number is "not random".
  ///
  /// Only the digits are looked at (the letters of the prefix are ignored) and
  /// at least 6 digits are needed. Returns a short reason when the digits are
  ///  * all the same digit (0000000, 1111111),
  ///  * counting up or down in order (1234567, 7654321, 8901234), or
  ///  * two digits repeating one after the other (1212121).
  /// Returns null when the serial looks random (or has too few digits).
  static String? serialPatternName(String serial) {
    final digits = serial.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 6) return null;
    final d = [for (final c in digits.split('')) int.parse(c)];

    if (d.every((x) => x == d.first)) {
      return 'the same digit repeated';
    }
    bool step(int by) {
      for (var i = 1; i < d.length; i++) {
        if ((d[i] - d[i - 1] + 10) % 10 != by) return false;
      }
      return true;
    }

    if (step(1)) return 'digits counting up in order';
    if (step(9)) return 'digits counting down in order';
    var alternating = d[0] != d[1];
    for (var i = 2; i < d.length && alternating; i++) {
      if (d[i] != d[i - 2]) alternating = false;
    }
    if (alternating) return 'two digits repeating';
    return null;
  }

  /// Summary text used when a check was skipped because the YOLO11s
  /// detector gave no result for that feature.
  static const _noDetector = 'Not checked · needs the YOLO11s detector';

  /// Compares a detected box count with the expected count.
  /// Confirmed count right → pass. Too few confirmed, but low-confidence
  /// boxes could make up the difference → unclear. Otherwise → fail.
  static CheckStatus _countStatus(FeatureDetectionModel d, int expected) {
    if (d.count == expected) return CheckStatus.pass;
    if (d.count < expected && d.count + d.uncertainCount >= expected) {
      return CheckStatus.inconclusive;
    }
    return CheckStatus.fail;
  }

  /// Combines several statuses into one: any fail wins, then any
  /// inconclusive, otherwise pass. Used when front and back are both counted.
  static CheckStatus _worst(Iterable<CheckStatus> all) {
    if (all.contains(CheckStatus.fail)) return CheckStatus.fail;
    if (all.contains(CheckStatus.inconclusive)) return CheckStatus.inconclusive;
    return CheckStatus.pass;
  }

  /// Small text suffix such as " (+1 low-confidence)" for the detail rows.
  static String _uncertain(FeatureDetectionModel d) =>
      d.uncertainCount > 0 ? ' (+${d.uncertainCount} low-confidence)' : '';

  // ---------------------------------------------------------------------------
  // ---- Check: SBP seals ----
  // ---------------------------------------------------------------------------

  /// Check 3: count the State Bank of Pakistan seals. Rule: exactly 1 on the
  /// front and exactly 3 on the back. Applies to all notes.
  ///  * skipped: no detector output for a side.
  ///  * inconclusive: seal confidence below minimum, or a count that is too
  ///    low but could be completed by low-confidence boxes.
  ///  * pass: both counts are right. fail: any other count.
  /// Weight 15: seals are hard to copy and the count is simple to verify.
  FeatureCheckModel _sbpSeals(SideDetectionModel f, SideDetectionModel b) {
    final fs = f.sbpSeals;
    final bs = b.sbpSeals;
    if (fs == null || bs == null) {
      return _check(
        id: FeatureCheckId.sbpSeals,
        title: 'SBP Seal Count',
        weight: ScoreWeights.sbpSeals,
        status: CheckStatus.skipped,
        summary: _noDetector,
      );
    }
    final fc = fs.count;
    final bc = bs.count;
    final summary = 'Front: $fc/${CurrencyRules.frontSbpSeals} | '
        'Back: $bc/${CurrencyRules.backSbpSeals}';
    final details = [
      CheckDetailModel(
        label: 'Front seals',
        value: '$fc of ${CurrencyRules.frontSbpSeals}${_uncertain(fs)} · '
            '${_pct(fs.confidence)}',
        ok: fc == CurrencyRules.frontSbpSeals,
      ),
      CheckDetailModel(
        label: 'Back seals',
        value: '$bc of ${CurrencyRules.backSbpSeals}${_uncertain(bs)} · '
            '${_pct(bs.confidence)}',
        ok: bc == CurrencyRules.backSbpSeals,
      ),
    ];

    if (fs.confidence < _minConf || bs.confidence < _minConf) {
      return _check(
        id: FeatureCheckId.sbpSeals,
        title: 'SBP Seal Count',
        weight: ScoreWeights.sbpSeals,
        status: CheckStatus.inconclusive,
        summary: 'Seal detections below confidence threshold',
        details: details,
      );
    }

    final status = _worst([
      _countStatus(fs, CurrencyRules.frontSbpSeals),
      _countStatus(bs, CurrencyRules.backSbpSeals),
    ]);
    return _check(
      id: FeatureCheckId.sbpSeals,
      title: 'SBP Seal Count',
      weight: ScoreWeights.sbpSeals,
      status: status,
      summary: status == CheckStatus.inconclusive
          ? '$summary · low-confidence seals, retake closer'
          : summary,
      confidence: math.min(fs.confidence, bs.confidence),
      details: details,
    );
  }

  // ---------------------------------------------------------------------------
  // ---- Check: lines / dots (denomination mark) ----
  // ---------------------------------------------------------------------------

  /// Check 4: lines (Rs 20/50/100) or dots (Rs 500/1000/5000) on the front.
  /// Rs 10 has neither, so it must show none of them.
  ///
  /// Weight 15. Not critical.
  ///  * inconclusive: denomination unknown, only one detector output, or the
  ///    marks were only faintly seen.
  ///  * skipped: no detector output for either mark type.
  ///
  /// YOLO11s labels a whole group of marks as ONE box (e.g. both Rs 1,000
  /// dots inside a single `security_dots` box), so box count is not mark
  /// count. The rule is: the note's own mark type is present (1 box up to
  /// one box per mark) and the other mark type is absent. Individual marks
  /// counted inside the box are shown as supporting detail.
  FeatureCheckModel _linesDots(
    SideDetectionModel f,
    FeatureCheckModel denominationCheck,
  ) {
    const title = 'Denomination Mark';
    final spec = CurrencyRules.denominations[f.denomination];
    if (spec == null || denominationCheck.status == CheckStatus.inconclusive) {
      return _check(
        id: FeatureCheckId.linesDots,
        title: title,
        weight: ScoreWeights.linesDots,
        status: CheckStatus.inconclusive,
        summary: 'Expected lines/dots unknown without a valid denomination',
      );
    }

    final lines = f.securityLines;
    final dots = f.securityDots;
    if (lines == null && dots == null) {
      return _check(
        id: FeatureCheckId.linesDots,
        title: title,
        weight: ScoreWeights.linesDots,
        status: CheckStatus.skipped,
        summary: _noDetector,
      );
    }
    if (lines == null || dots == null) {
      return _check(
        id: FeatureCheckId.linesDots,
        title: title,
        weight: ScoreWeights.linesDots,
        status: CheckStatus.inconclusive,
        summary: 'Lines/dots could not be inspected reliably',
      );
    }

    // Rs 10 case: no lines or dots are allowed at all.
    final rs = formatRupees(spec.value);
    String plural(int n, String one) => n == 1 ? one : '${one}s';

    if (spec.mark == DenominationMark.none) {
      final clean = lines.count == 0 && dots.count == 0;
      return _check(
        id: FeatureCheckId.linesDots,
        title: title,
        weight: ScoreWeights.linesDots,
        status: clean ? CheckStatus.pass : CheckStatus.fail,
        summary: clean
            ? 'No lines or dots expected for $rs · none found'
            : 'Unexpected marks on $rs: ${lines.count} line, '
                '${dots.count} dot regions',
        confidence: math.min(lines.confidence, dots.confidence),
      );
    }

    // Other notes: pick the mark type this note should have ("mine") and
    // the wrong type ("other"), then decide.
    final usesDots = spec.mark == DenominationMark.dots;
    final mine = usesDots ? dots : lines;
    final other = usesDots ? lines : dots;
    final kind = usesDots ? 'dot' : 'line';
    final otherKind = usesDots ? 'lines' : 'dots';
    final n = spec.markCount;

    final CheckStatus status;
    final String summary;
    // STRICT RULE: the note must show EXACTLY the required number of its own
    // mark (Rs 20: 1 line, Rs 50: 2, Rs 100: 3, Rs 500: 1 dot, Rs 1,000: 2,
    // Rs 5,000: 3) and none of the other type. Fewer or more is a FAIL, which
    // makes the whole note FAKE even when every other feature passes.
    // The only exception is a mark seen so faintly that nothing was counted:
    // that is "unclear" (retake), not a fail.
    final seen = mine.observedMarks;
    if (other.observedMarks > 0) {
      status = CheckStatus.fail;
      summary = 'Security $otherKind found, but $rs uses ${plural(n, kind)}';
    } else if (seen == 0) {
      status = mine.uncertainCount > 0
          ? CheckStatus.inconclusive
          : CheckStatus.fail;
      summary = status == CheckStatus.inconclusive
          ? 'Security ${kind}s only faintly detected · retake in better light'
          : 'No security ${kind}s found ($rs needs $n)';
    } else if (seen != n) {
      status = CheckStatus.fail;
      summary = '$seen ${plural(seen, kind)} found, $rs needs exactly $n';
    } else {
      status = CheckStatus.pass;
      summary = 'Security ${plural(n, kind)}: $n of $n counted';
    }

    return _check(
      id: FeatureCheckId.linesDots,
      title: title,
      weight: ScoreWeights.linesDots,
      status: status,
      summary: summary,
      confidence: mine.count > 0 ? mine.confidence : 1,
      details: [
        CheckDetailModel(
          label: 'Expected for $rs',
          value: '$n ${plural(n, kind)}',
        ),
        CheckDetailModel(
          label: 'Security $kind regions (YOLO)',
          value: '${mine.count}${_uncertain(mine)}'
              '${mine.count > 0 ? ' · ${_pct(mine.confidence)}' : ''}',
        ),
        CheckDetailModel(
          label: '${kind[0].toUpperCase()}${kind.substring(1)}s counted',
          value: '$seen of $n required',
          ok: seen == n,
        ),
        CheckDetailModel(
          label: 'Security $otherKind (must be absent)',
          value: '${other.count}${_uncertain(other)}',
          ok: other.observedMarks == 0,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // ---- Check: security thread ----
  // ---------------------------------------------------------------------------

  /// Check 5: a note that carries a security thread must show exactly ONE
  /// (never 2 or 3), on the front, and on the back if the back was read.
  ///  * notApplicable: Rs 10, 20 and 50 have no thread.
  ///  * skipped: no detector output on either side.
  ///  * inconclusive: front missing or confidence below minimum.
  ///  * pass: count is 1 on each side checked. fail: any other count.
  /// Weight 10. Not critical.
  FeatureCheckModel _thread(SideDetectionModel f, SideDetectionModel b) {
    const title = 'Security Thread';
    final spec = CurrencyRules.denominations[f.denomination];
    if (spec != null && !spec.hasThread) {
      return _check(
        id: FeatureCheckId.securityThread,
        title: title,
        weight: ScoreWeights.securityThread,
        status: CheckStatus.notApplicable,
        summary: '${formatRupees(spec.value)} has no security thread',
      );
    }

    final ft = f.securityThreads;
    final bt = b.securityThreads;
    if (ft == null && bt == null) {
      return _check(
        id: FeatureCheckId.securityThread,
        title: title,
        weight: ScoreWeights.securityThread,
        status: CheckStatus.skipped,
        summary: _noDetector,
      );
    }
    if (ft == null ||
        ft.confidence < _minConf ||
        (bt != null && bt.confidence < _minConf)) {
      return _check(
        id: FeatureCheckId.securityThread,
        title: title,
        weight: ScoreWeights.securityThread,
        status: CheckStatus.inconclusive,
        summary: 'Thread could not be inspected reliably',
      );
    }

    const expected = CurrencyRules.securityThreads;
    final status = _worst([
      _countStatus(ft, expected),
      if (bt != null) _countStatus(bt, expected),
    ]);
    return _check(
      id: FeatureCheckId.securityThread,
      title: title,
      weight: ScoreWeights.securityThread,
      status: status,
      summary: switch (status) {
        CheckStatus.pass => 'Detected: ${ft.count} (exactly $expected required)',
        CheckStatus.inconclusive =>
          'Thread only faintly detected · tilt the note so the thread shows',
        _ => 'Detected: ${ft.count}${bt != null ? ' front / ${bt.count} back' : ''}'
            ' — exactly $expected required',
      },
      confidence: math.min(ft.confidence, bt?.confidence ?? 1),
      details: [
        CheckDetailModel(
          label: 'Front',
          value: '${ft.count}${_uncertain(ft)} · ${_pct(ft.confidence)}',
          ok: ft.count == expected,
        ),
        if (bt != null)
          CheckDetailModel(
            label: 'Back',
            value: '${bt.count} · ${_pct(bt.confidence)}',
            ok: bt.count == expected,
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // ---- Check: printed year and layout ----
  // ---------------------------------------------------------------------------

  /// Check 6: the printed year region must exist on the front, and if the
  /// year was read it must be sensible: from 1947 (Pakistan's start) up to
  /// the current year. Applies to all notes.
  ///  * inconclusive: region found but confidence below minimum.
  ///  * fail: region missing, or the year is outside that range.
  ///  * pass: region present and year plausible (or year text not read).
  /// Weight 5, the smallest: the year is easy to misread by OCR, so it is
  /// only a light supporting sign.
  FeatureCheckModel _printedYear(SideDetectionModel f) {
    const title = 'Printed Year & Layout';
    final y = f.printedYear;
    if (y != null && y.detected && y.confidence < _minConf) {
      return _check(
        id: FeatureCheckId.printedYear,
        title: title,
        weight: ScoreWeights.printedYear,
        status: CheckStatus.inconclusive,
        summary: 'Printed year region unclear',
      );
    }
    if (y == null || !y.detected) {
      return _check(
        id: FeatureCheckId.printedYear,
        title: title,
        weight: ScoreWeights.printedYear,
        status: CheckStatus.fail,
        summary: 'Printed year missing on the front',
        details: const [
          CheckDetailModel(label: 'Printed year', value: 'Not found', ok: false),
        ],
      );
    }

    final year = int.tryParse(y.value ?? '');
    final sane = y.value == null ||
        (year != null &&
            year >= CurrencyRules.earliestPrintedYear &&
            year <= _now.year);
    return _check(
      id: FeatureCheckId.printedYear,
      title: title,
      weight: ScoreWeights.printedYear,
      status: sane ? CheckStatus.pass : CheckStatus.fail,
      summary: sane
          ? 'Year ${y.value ?? 'present'} · layout consistent'
          : 'Implausible printed year "${y.value}"',
      confidence: y.confidence,
      details: [
        CheckDetailModel(
          label: 'Printed year',
          value: '${y.value ?? 'present'} · ${_pct(y.confidence)}',
          ok: sane,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // ---- Check: Rs 5,000 alteration CNN ----
  // ---------------------------------------------------------------------------

  /// Check 7 (Rs 5,000 only): the alteration classifier gives an "altered
  /// probability". Fail if it is a strong anomaly (at or over its threshold).
  ///  * notApplicable: [notApplicable] text is set (not a Rs 5,000 note).
  ///  * skipped: the model did not run ([skipReason] explains).
  ///  * pass / fail: from the model's own strong-anomaly flag.
  /// Weight 10. Supporting evidence, not critical.
  FeatureCheckModel _surface(
    AnomalyModel? a,
    String? skipReason,
    String? notApplicable,
  ) {
    const title = 'Rs 5,000 Alteration Score (CNN)';
    if (notApplicable != null) {
      return _check(
        id: FeatureCheckId.surfaceAnomaly,
        title: title,
        weight: ScoreWeights.surfaceAnomaly,
        status: CheckStatus.notApplicable,
        summary: notApplicable,
      );
    }
    if (a == null) {
      return _check(
        id: FeatureCheckId.surfaceAnomaly,
        title: title,
        weight: ScoreWeights.surfaceAnomaly,
        status: CheckStatus.skipped,
        summary: skipReason ?? 'Anomaly model did not run',
      );
    }

    final ok = !a.isStrongAnomaly;
    // Map anomaly 0..threshold onto the same 0.5..1 confidence range used by
    // the detectors so the pass factor stays comparable.
    final consistency =
        1 - (a.anomalyScore / a.threshold).clamp(0.0, 1.0) * (1 - _minConf);
    return _check(
      id: FeatureCheckId.surfaceAnomaly,
      title: title,
      weight: ScoreWeights.surfaceAnomaly,
      status: ok ? CheckStatus.pass : CheckStatus.fail,
      summary: ok
          ? 'Altered probability ${a.anomalyScore.toStringAsFixed(2)} · no synthetic alteration'
          : 'Synthetic alteration suspected (${a.anomalyScore.toStringAsFixed(2)})',
      confidence: consistency,
      details: [
        CheckDetailModel(label: 'Model', value: a.model),
        if (a.frontScore != null)
          CheckDetailModel(
            label: 'Front altered probability',
            value: a.frontScore!.toStringAsFixed(3),
            ok: a.frontScore! < a.threshold,
          ),
        if (a.backScore != null)
          CheckDetailModel(
            label: 'Back altered probability',
            value: a.backScore!.toStringAsFixed(3),
            ok: a.backScore! < a.threshold,
          ),
        CheckDetailModel(
          label: 'Anomaly score',
          value: a.anomalyScore.toStringAsFixed(3),
          ok: ok,
        ),
        CheckDetailModel(
          label: 'Threshold',
          value: a.threshold.toStringAsFixed(2),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // ---- Check: Rs 5,000 genuine / counterfeit CNN ----
  // ---------------------------------------------------------------------------

  /// Check 8 (Rs 5,000 only): second, independent CNN: genuine vs
  /// counterfeit. Supporting evidence like the alteration CNN; YOLO and OCR
  /// rules still decide the physical checks.
  ///  * notApplicable: not a Rs 5,000 note.
  ///  * skipped: classifier did not run.
  ///  * fail: the model flags counterfeit (probability at or over its
  ///    threshold). pass: otherwise.
  /// Weight 10.
  FeatureCheckModel _counterfeitCnn(CounterfeitCnnModel? c, String? notApplicable) {
    const title = 'Rs 5,000 Genuine/Counterfeit (CNN)';
    if (notApplicable != null) {
      return _check(
        id: FeatureCheckId.counterfeitCnn,
        title: title,
        weight: ScoreWeights.counterfeitCnn,
        status: CheckStatus.notApplicable,
        summary: notApplicable,
      );
    }
    if (c == null) {
      return _check(
        id: FeatureCheckId.counterfeitCnn,
        title: title,
        weight: ScoreWeights.counterfeitCnn,
        status: CheckStatus.skipped,
        summary: 'Classifier did not run',
      );
    }

    final ok = !c.flagsCounterfeit;
    final p = c.counterfeitProbability;
    return _check(
      id: FeatureCheckId.counterfeitCnn,
      title: title,
      weight: ScoreWeights.counterfeitCnn,
      status: ok ? CheckStatus.pass : CheckStatus.fail,
      summary: ok
          ? 'Classified genuine · P(counterfeit) ${p.toStringAsFixed(2)}'
          : 'Classified counterfeit · P(counterfeit) ${p.toStringAsFixed(2)}',
      // Same mapping as the alteration CNN: 0 → full confidence.
      confidence: 1 - (p / c.threshold).clamp(0.0, 1.0) * (1 - _minConf),
      details: [
        CheckDetailModel(label: 'Model', value: c.model),
        CheckDetailModel(
          label: 'Front P(counterfeit)',
          value: c.frontCounterfeit.toStringAsFixed(3),
          ok: c.frontCounterfeit < c.threshold,
        ),
        CheckDetailModel(
          label: 'Back P(counterfeit)',
          value: c.backCounterfeit.toStringAsFixed(3),
          ok: c.backCounterfeit < c.threshold,
        ),
        CheckDetailModel(
          label: 'Threshold',
          value: c.threshold.toStringAsFixed(2),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // ---- Check: small CNN (Rs 10-1,000) - CURRENTLY SWITCHED OFF ----
  // ---------------------------------------------------------------------------

  /// Check 9: MobileNetV3-Small genuine/fake classifier for Rs 10–1,000.
  /// It is switched off while kSmallCnnEnabled (currency_rules.dart) is
  /// false, so evaluate() does not call this and no row is shown.
  ///
  /// Supporting evidence like the Rs 5,000 CNNs: a genuine-like score never
  /// overrides a failed physical check, and a classifier that could not run
  /// is "unable to verify", never an implicit pass.
  ///  * notApplicable: Rs 5,000 (it has its own two CNNs) or unknown value.
  ///  * inconclusive: [skipReason] is set (the model could not run).
  ///  * skipped: no output. fail / pass: from the model's threshold.
  /// Weight 10.
  FeatureCheckModel _smallCnn(
    CounterfeitCnnModel? c,
    String? skipReason,
    int? denomination,
  ) {
    const title = 'Genuine/Fake (CNN)';
    if (denomination == null || denomination == 5000) {
      return _check(
        id: FeatureCheckId.smallCnn,
        title: title,
        weight: ScoreWeights.smallCnn,
        status: CheckStatus.notApplicable,
        summary: denomination == 5000
            ? 'Rs 5,000 uses its own two classifiers'
            : 'Denomination unknown',
      );
    }
    if (skipReason != null) {
      return _check(
        id: FeatureCheckId.smallCnn,
        title: title,
        weight: ScoreWeights.smallCnn,
        status: CheckStatus.inconclusive,
        summary: skipReason,
      );
    }
    if (c == null) {
      return _check(
        id: FeatureCheckId.smallCnn,
        title: title,
        weight: ScoreWeights.smallCnn,
        status: CheckStatus.skipped,
        summary: 'Classifier did not run',
      );
    }

    final ok = !c.flagsCounterfeit;
    final p = c.counterfeitProbability;
    return _check(
      id: FeatureCheckId.smallCnn,
      title: title,
      weight: ScoreWeights.smallCnn,
      status: ok ? CheckStatus.pass : CheckStatus.fail,
      summary: ok
          ? 'Classified genuine · P(fake) ${p.toStringAsFixed(2)}'
          : 'Classified fake · P(fake) ${p.toStringAsFixed(2)}',
      confidence: 1 - (p / c.threshold).clamp(0.0, 1.0) * (1 - _minConf),
      details: [
        CheckDetailModel(label: 'Model', value: c.model),
        CheckDetailModel(
          label: 'Front P(fake)',
          value: c.frontCounterfeit.toStringAsFixed(3),
          ok: c.frontCounterfeit < c.threshold,
        ),
        CheckDetailModel(
          label: 'Back P(fake)',
          value: c.backCounterfeit.toStringAsFixed(3),
          ok: c.backCounterfeit < c.threshold,
        ),
        CheckDetailModel(
          label: 'Threshold',
          value: c.threshold.toStringAsFixed(2),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // ---- Check: edge microprint ----
  // ---------------------------------------------------------------------------

  /// Check 10: tiny repeated denomination text along the border (Rs 5,000
  /// only for now). Read by OCR without any trained model. Not readable is
  /// "not checked", never fake; only a clearly repeated *different* value
  /// fails.
  ///  * notApplicable: any note except Rs 5,000.
  ///  * skipped: no read, or fewer than 3 repeats (too small to read).
  ///  * fail: the border repeats a different value.
  ///  * pass: the expected text is read at least 3 times. The minimum of 3
  ///    stops one corner numeral being mistaken for microprint.
  /// Weight 5: OCR of tiny print is unreliable, so it only adds a little.
  FeatureCheckModel _microprint(MicroprintModel? m, int? denomination) {
    const title = 'Edge Microprint';
    if (!CurrencyRules.hasMicroprint(denomination)) {
      return _check(
        id: FeatureCheckId.microprint,
        title: title,
        weight: ScoreWeights.microprint,
        status: CheckStatus.notApplicable,
        summary: denomination == null
            ? 'Denomination unknown'
            : 'Microprint is only checked on Rs 5,000 for now',
      );
    }
    final rs = formatRupees(denomination!);
    if (m == null) {
      return _check(
        id: FeatureCheckId.microprint,
        title: title,
        weight: ScoreWeights.microprint,
        status: CheckStatus.skipped,
        summary: 'Not read',
      );
    }

    final source = m.source == 'close-up' ? 'close-up' : 'scan';
    final details = [
      CheckDetailModel(label: 'Expected text', value: '"${m.expected}" repeated'),
      CheckDetailModel(
        label: 'Found ($source)',
        value: '${m.occurrences}× (need ${CurrencyRules.microprintMinOccurrences})',
        ok: m.occurrences >= CurrencyRules.microprintMinOccurrences ? true : null,
      ),
      if (m.conflicting != null)
        CheckDetailModel(
          label: 'Different value repeated',
          value: '"${m.conflicting}" ${m.conflictingOccurrences}×',
          ok: false,
        ),
      if (m.sample.isNotEmpty) CheckDetailModel(label: 'OCR read', value: m.sample),
    ];

    if (m.conflicting != null) {
      return _check(
        id: FeatureCheckId.microprint,
        title: title,
        weight: ScoreWeights.microprint,
        status: CheckStatus.fail,
        summary: 'Border repeats "${m.conflicting}", but this is $rs',
        details: details,
      );
    }
    if (m.occurrences >= CurrencyRules.microprintMinOccurrences) {
      return _check(
        id: FeatureCheckId.microprint,
        title: title,
        weight: ScoreWeights.microprint,
        status: CheckStatus.pass,
        summary: '"${m.expected}" read ${m.occurrences}× along the border ($source)',
        // More repeats read → more confidence, capped.
        confidence: (0.6 + 0.08 * m.occurrences).clamp(0.6, 1.0),
        details: details,
      );
    }
    return _check(
      id: FeatureCheckId.microprint,
      title: title,
      weight: ScoreWeights.microprint,
      status: CheckStatus.skipped,
      summary: m.source == 'close-up'
          ? 'Close-up still not sharp enough to read · try again closer'
          : 'Too small to read in the full scan · tap "Check microprint close-up"',
      details: details,
    );
  }

  // ---------------------------------------------------------------------------
  // ---- Check: back-side monument ----
  // ---------------------------------------------------------------------------

  /// Check 11: back-side monument (Teachable Machine / MobileNet classifier).
  /// Pass: the note's own monument with ≥ 0.60. Fail (→ FAKE): another
  /// monument or 'invalid' with ≥ 0.60. Below 0.60: not checked, never fail.
  ///  * skipped: model missing, not trained on this denomination, unknown
  ///    denomination, or confidence under 0.60.
  ///  * warning: the model is still preliminary (not "verified"), so a
  ///    mismatch is only reported and does not change the score.
  ///  * fail: a verified model confidently sees a different monument.
  ///    Critical, and evaluate() turns it into a FAKE result.
  /// Weight 20: a wrong picture on the back is a strong sign of a bad note.
  FeatureCheckModel _monument(MonumentResultModel? m, int? denomination) {
    const title = 'Backside Monument';
    FeatureCheckModel skipped(String summary) => _check(
          id: FeatureCheckId.monument,
          title: title,
          weight: ScoreWeights.monument,
          status: CheckStatus.skipped,
          summary: summary,
        );

    if (m == null) return skipped('Not run');
    if (!m.modelAvailable) {
      return skipped('Monument model not installed '
          '(assets/models/monument_classifier.tflite)');
    }
    final expectedName = CurrencyRules.monuments[denomination];
    if (denomination == null || expectedName == null) {
      return skipped('Denomination unknown, so the expected monument is unknown');
    }
    if (m.knownDenominations.isNotEmpty &&
        !m.knownDenominations.contains(denomination)) {
      return skipped('Monument model not trained on Rs $denomination yet');
    }

    final seenDenom = m.denomination;
    final seenName = seenDenom == null
        ? 'no valid monument'
        : '${CurrencyRules.monuments[seenDenom]} (Rs $seenDenom)';
    final details = [
      CheckDetailModel(label: 'Expected', value: '$expectedName (Rs $denomination)'),
      CheckDetailModel(
        label: 'Model says',
        value: '${m.label ?? '—'} · ${_pct(m.confidence)}',
        ok: m.confidence < CurrencyRules.monumentMinConfidence
            ? null
            : seenDenom == denomination,
      ),
    ];

    if (m.confidence < CurrencyRules.monumentMinConfidence) {
      return _check(
        id: FeatureCheckId.monument,
        title: title,
        weight: ScoreWeights.monument,
        status: CheckStatus.skipped,
        summary: 'Monument not clear (${_pct(m.confidence)}) · '
            'take a clearer photo',
        details: details,
      );
    }
    if (seenDenom == denomination) {
      return _check(
        id: FeatureCheckId.monument,
        title: title,
        weight: ScoreWeights.monument,
        status: CheckStatus.pass,
        summary: 'Back side verified – $expectedName matched',
        confidence: m.confidence,
        details: details,
      );
    }
    if (!m.verified) {
      // Preliminary model: report, but never call the note fake.
      return _check(
        id: FeatureCheckId.monument,
        title: title,
        weight: ScoreWeights.monument,
        status: CheckStatus.warning,
        summary: 'Monument looks like $seenName, expected $expectedName · '
            'preliminary model, please check the back yourself',
        details: details,
      );
    }
    return _check(
      id: FeatureCheckId.monument,
      title: title,
      weight: ScoreWeights.monument,
      status: CheckStatus.fail,
      summary: 'Wrong back side: this is not a genuine Rs $denomination note '
          '($seenName instead of $expectedName)',
      critical: true,
      details: details,
    );
  }

  // ---------------------------------------------------------------------------
  // ---- Check: front-side Quaid-e-Azam portrait ----
  // ---------------------------------------------------------------------------

  /// Check 12: the Quaid-e-Azam portrait on the FRONT (same method as the
  /// monument check on the back). Pass: the note's own portrait design with
  /// >= 0.60. Fail (-> FAKE): another value's design or 'invalid' with >= 0.60.
  /// Below 0.60: not checked, never fail.
  ///  * skipped: model missing, not trained on this denomination, unknown
  ///    denomination, or confidence under 0.60.
  ///  * warning: the model is preliminary (not "verified"): reported only.
  ///  * fail: a verified model confidently sees a different front.
  /// Weight 10. Critical, and evaluate() turns it into a FAKE result.
  FeatureCheckModel _portrait(PortraitResultModel? p, int? denomination) {
    const title = 'Quaid-e-Azam Portrait';
    FeatureCheckModel skipped(String summary) => _check(
          id: FeatureCheckId.portrait,
          title: title,
          weight: ScoreWeights.portrait,
          status: CheckStatus.skipped,
          summary: summary,
        );

    if (p == null) return skipped('Not run');
    if (!p.modelAvailable) {
      return skipped('Portrait model not installed '
          '(assets/models/portrait_classifier.tflite)');
    }
    if (denomination == null || !CurrencyRules.isSupported(denomination)) {
      return skipped('Denomination unknown, so the expected portrait is unknown');
    }
    if (p.knownDenominations.isNotEmpty &&
        !p.knownDenominations.contains(denomination)) {
      return skipped('Portrait model not trained on Rs $denomination yet');
    }

    final seenDenom = p.denomination;
    final seenName =
        seenDenom == null ? 'no valid portrait' : 'the Rs $seenDenom portrait';
    final details = [
      CheckDetailModel(
          label: 'Expected', value: 'Quaid-e-Azam portrait of Rs $denomination'),
      CheckDetailModel(
        label: 'Model says',
        value: '${p.label ?? '—'} · ${_pct(p.confidence)}',
        ok: p.confidence < CurrencyRules.portraitMinConfidence
            ? null
            : seenDenom == denomination,
      ),
    ];

    if (p.confidence < CurrencyRules.portraitMinConfidence) {
      return _check(
        id: FeatureCheckId.portrait,
        title: title,
        weight: ScoreWeights.portrait,
        status: CheckStatus.skipped,
        summary: 'Portrait not clear (${_pct(p.confidence)}) · '
            'take a clearer photo of the front',
        details: details,
      );
    }
    if (seenDenom == denomination) {
      return _check(
        id: FeatureCheckId.portrait,
        title: title,
        weight: ScoreWeights.portrait,
        status: CheckStatus.pass,
        summary: 'Front side verified – Quaid-e-Azam portrait matched',
        confidence: p.confidence,
        details: details,
      );
    }
    if (!p.verified) {
      return _check(
        id: FeatureCheckId.portrait,
        title: title,
        weight: ScoreWeights.portrait,
        status: CheckStatus.warning,
        summary: 'Front looks like $seenName, expected the Rs $denomination '
            'design · preliminary model, please check the front yourself',
        details: details,
      );
    }
    return _check(
      id: FeatureCheckId.portrait,
      title: title,
      weight: ScoreWeights.portrait,
      status: CheckStatus.fail,
      summary: 'Wrong front side: the portrait side does not match a genuine '
          'Rs $denomination note ($seenName instead)',
      critical: true,
      details: details,
    );
  }

  /// Formats 0..1 as a whole-number percent, for example 0.87 -> "87%".
  static String _pct(double v) => '${(v * 100).round()}%';
}
