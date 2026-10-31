import 'dart:math' as math;

import '../data/models/confidence_score_model.dart';
import '../data/models/feature_check_model.dart';
import '../data/models/note_analysis_model.dart';
import '../data/models/verification_result_model.dart';
import 'currency_rules.dart';

/// Applies the project's verification rules to raw detector output and
/// produces a verdict plus an authenticity confidence percentage.
///
/// Pure and synchronous so it can be unit-tested without Flutter.
class VerificationEngine {
  const VerificationEngine({this._clock});

  final DateTime Function()? _clock;

  DateTime get _now => (_clock ?? DateTime.now)();

  static const double _minConf = CurrencyRules.minDetectionConfidence;

  /// Score earned by a passing feature: 85% of its weight at the minimum
  /// accepted confidence, rising to 100% at full confidence. This guarantees
  /// that a note passing every check always lands in the "real" band.
  static double _passFactor(double confidence) {
    final normalised =
        ((confidence - _minConf) / (1 - _minConf)).clamp(0.0, 1.0);
    return 0.85 + 0.15 * normalised;
  }

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

  /// Result for images rejected by the on-device banknote gate.
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

  VerificationResultModel evaluate(
    NoteAnalysisModel analysis, {
    String source = 'api',
  }) {
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
          'Jaali Note / Fake Note – Ye photocopy lag rahi hai.',
          'This looks like a photocopy or printout on paper, not a real note.',
          ...analysis.rejectionReasons,
        ],
        analyzedAt: _now,
        analysis: analysis,
        source: source,
      );
    }

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

    final front = analysis.front;
    final back = analysis.back;
    if (front == null || back == null) {
      return _unable(
        analysis,
        source,
        ['The detector did not return results for both sides.'],
      );
    }

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
      // Microprint is only checked on Rs 5,000 for now; other notes get no
      // microprint row at all.
      if (CurrencyRules.hasMicroprint(front.denomination))
        _microprint(analysis.microprint, front.denomination),
      _monument(
        analysis.monument,
        _agreedDenomination(front, back) ?? front.denomination,
      ),
    ];

    final scored = checks.where((c) =>
        c.status != CheckStatus.skipped &&
        c.status != CheckStatus.notApplicable &&
        c.status != CheckStatus.warning);
    final totalWeight = scored.fold<double>(0, (s, c) => s + c.weight);
    final earned = scored.fold<double>(0, (s, c) => s + c.earned);
    final raw = totalWeight == 0 ? 0.0 : earned / totalWeight * 100;

    final failures = checks.where((c) => c.failed).toList();
    final critical = failures.where((c) => c.isCritical).toList();
    final inconclusive =
        checks.where((c) => c.status == CheckStatus.inconclusive).toList();

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

    late final int pct;
    var penalty = PenaltyType.none;
    String? penaltyReason;

    if (critical.isNotEmpty) {
      pct = math.min(
        (raw * ScoreWeights.criticalPenalty).round(),
        ScoreWeights.criticalCap,
      );
      penalty = PenaltyType.criticalFailure;
      penaltyReason =
          'Critical failure: ${critical.map((c) => c.title).join(', ')}';
    } else if (failures.isNotEmpty) {
      pct = math.min(
        (raw * math.pow(ScoreWeights.featurePenalty, failures.length)).round(),
        ScoreWeights.featureCap,
      );
      penalty = PenaltyType.featureFailure;
      penaltyReason =
          'Failed requirement: ${failures.map((c) => c.title).join(', ')}';
    } else {
      pct = raw.round();
    }

    final band = ConfidenceScoreModel.bandFor(pct);
    // Below the PASSED line every outcome is SUSPICIOUS; the score and its
    // colour show how severe it is.
    // A confidently wrong back-side monument means FAKE, even if every
    // other check passed.
    final monumentFailed = checks.any(
        (c) => c.id == FeatureCheckId.monument && c.status == CheckStatus.fail);
    final verdict = monumentFailed
        ? VerificationVerdict.fake
        : band == ScoreBand.authentic
            ? VerificationVerdict.real
            : VerificationVerdict.suspicious;
    final denom = _agreedDenomination(front, back) ?? front.denomination;

    final skipped =
        checks.where((c) => c.status == CheckStatus.skipped).toList();
    final messages = <String>[
      if (monumentFailed && denom != null) ...[
        'Fake Note – Backside monument mismatch. $denom rupay pe '
            '${CurrencyRules.monuments[denom]} honi chahiye.',
        'Back side galat hai – Ye $denom ka asli note nahi lag raha.',
      ],
      if (failures.isEmpty && skipped.isEmpty)
        analysis.rs5000OnlyReason == null
            ? 'All YOLO11s security features and OCR serial checks passed, '
                'and both Rs 5,000 CNNs found nothing wrong.'
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
        'Microprint unreadable – verified by alternate features '
            '(Microprint parhi nahi ja saki – baqi features se tasdeeq hui).',
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

  int? _agreedDenomination(SideDetectionModel f, SideDetectionModel b) =>
      f.denomination != null && f.denomination == b.denomination
          ? f.denomination
          : null;

  String _rs(int? v) => v == null ? '—' : formatRupees(v);

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

  static const _noDetector = 'Not checked · needs the YOLO11s detector';

  /// Confirmed count right → pass. Too few confirmed, but low-confidence
  /// boxes could make up the difference → unclear. Otherwise → fail.
  static CheckStatus _countStatus(FeatureDetectionModel d, int expected) {
    if (d.count == expected) return CheckStatus.pass;
    if (d.count < expected && d.count + d.uncertainCount >= expected) {
      return CheckStatus.inconclusive;
    }
    return CheckStatus.fail;
  }

  static CheckStatus _worst(Iterable<CheckStatus> all) {
    if (all.contains(CheckStatus.fail)) return CheckStatus.fail;
    if (all.contains(CheckStatus.inconclusive)) return CheckStatus.inconclusive;
    return CheckStatus.pass;
  }

  static String _uncertain(FeatureDetectionModel d) =>
      d.uncertainCount > 0 ? ' (+${d.uncertainCount} low-confidence)' : '';

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

  /// Lines (Rs 20/50/100) or dots (Rs 500/1000/5000) on the front.
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

    final usesDots = spec.mark == DenominationMark.dots;
    final mine = usesDots ? dots : lines;
    final other = usesDots ? lines : dots;
    final kind = usesDots ? 'dot' : 'line';
    final otherKind = usesDots ? 'lines' : 'dots';
    final n = spec.markCount;

    final CheckStatus status;
    final String summary;
    if (other.count > 0) {
      status = CheckStatus.fail;
      summary = 'Security $otherKind found, but $rs uses ${plural(n, kind)}';
    } else if (mine.count == 0) {
      status = mine.uncertainCount > 0
          ? CheckStatus.inconclusive
          : CheckStatus.fail;
      summary = status == CheckStatus.inconclusive
          ? 'Security ${kind}s only faintly detected · retake in better light'
          : 'No security ${kind}s found ($rs has $n)';
    } else if (mine.count > n) {
      status = CheckStatus.fail;
      summary = '${mine.count} $kind regions found ($rs has $n)';
    } else {
      status = CheckStatus.pass;
      final counted = mine.markCount;
      summary = counted == n
          ? 'Security ${plural(n, kind)}: $n of $n counted'
          : 'Security ${plural(n, kind)} region found ($rs has $n)';
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
          ok: mine.count >= 1 && mine.count <= n,
        ),
        if (mine.markCount != null)
          CheckDetailModel(
            label: '${kind[0].toUpperCase()}${kind.substring(1)}s counted in region',
            value: '${mine.markCount} of $n',
            ok: mine.markCount == n ? true : null,
          ),
        CheckDetailModel(
          label: 'Security $otherKind (must be absent)',
          value: '${other.count}${_uncertain(other)}',
          ok: other.count == 0,
        ),
      ],
    );
  }

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

  /// Second, independent Rs 5,000 CNN: genuine vs counterfeit. Supporting
  /// evidence like the alteration CNN; YOLO and OCR rules still decide the
  /// physical checks.
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

  /// Tiny repeated denomination text along the border (Rs 5,000 only for now).
  /// Read by OCR without any trained model. Not readable is "not checked",
  /// never fake; only a clearly repeated *different* value fails.
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

  /// Back-side monument (Teachable Machine / MobileNet classifier).
  /// Pass: the note's own monument with ≥ 0.60. Fail (→ FAKE): another
  /// monument or 'invalid' with ≥ 0.60. Below 0.60: not checked, never fail.
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
        summary: 'Thora saaf photo lein, monument clear nahi · '
            'Monument not clear (${_pct(m.confidence)})',
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
      summary: 'Back side galat hai – Ye $denomination ka asli note nahi lag '
          'raha ($seenName instead of $expectedName)',
      critical: true,
      details: details,
    );
  }

  static String _pct(double v) => '${(v * 100).round()}%';
}
