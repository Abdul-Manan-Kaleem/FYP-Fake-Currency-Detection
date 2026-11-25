// Raw detector output (YOLO11s + OCR + MobileNetV3) as returned by
// `POST /api/v1/verify`. The client-side VerificationEngine turns this into a
// verdict; the backend only reports what it saw.
//
// In the on-device app the same shape is filled in on the phone. Every model
// below can be read from / written to JSON.

/// Reads [v] as a double. Returns [fallback] if it is not a number.
double _d(Object? v, [double fallback = 0]) =>
    v is num ? v.toDouble() : fallback;

/// Reads [v] as an int. Accepts numbers and number text; otherwise null.
int? _i(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

/// Per-side capture quality metrics, each normalised to 0..1.
class ImageQualityModel {
  const ImageQualityModel({
    required this.blurScore,
    required this.glareScore,
    required this.brightness,
  });

  /// 0 = razor sharp, 1 = unusable.
  final double blurScore;

  /// 0 = no glare, 1 = fully blown-out highlights.
  final double glareScore;

  /// Mean luminance, 0 = black, 1 = white.
  final double brightness;

  /// Limits for a usable photo. Above/below these the photo has an issue.
  static const double maxBlur = 0.6;
  static const double maxGlare = 0.6;
  static const double minBrightness = 0.15;
  static const double maxBrightness = 0.92;

  /// Plain-English list of problems with this photo (empty if it is fine).
  List<String> get issues => [
        if (blurScore > maxBlur) 'High blur',
        if (glareScore > maxGlare) 'Severe glare',
        if (brightness < minBrightness) 'Too dark',
        if (brightness > maxBrightness) 'Over-exposed',
      ];

  /// True when the photo has no quality issues.
  bool get isUsable => issues.isEmpty;

  /// Builds quality values from JSON. Missing brightness defaults to 0.5
  /// (mid-grey) so a missing value does not look like a bad photo.
  factory ImageQualityModel.fromJson(Map<String, dynamic> json) =>
      ImageQualityModel(
        blurScore: _d(json['blur_score']),
        glareScore: _d(json['glare_score']),
        brightness: _d(json['brightness'], 0.5),
      );

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'blur_score': blurScore,
        'glare_score': glareScore,
        'brightness': brightness,
      };
}

/// A counted YOLO feature class (seals, threads, lines, dots).
class FeatureDetectionModel {
  const FeatureDetectionModel({
    required this.count,
    required this.confidence,
    this.uncertainCount = 0,
    this.markCount,
  });

  /// Detections at or above the confirmation threshold.
  final int count;

  /// Detections seen below the confirmation threshold. They never count,
  /// but if they could explain a wrong count the check is unclear, not failed.
  final int uncertainCount;

  /// For lines/dots: individual marks counted by pixel analysis inside the
  /// best YOLO box (YOLO labels a whole group as one box). Informational.
  final int? markCount;

  /// Number of individual lines/dots actually seen: separate YOLO boxes, or
  /// the marks counted inside one box, whichever is larger. This is the number
  /// the strict dots/lines rule compares with the required count.
  int get observedMarks =>
      markCount != null && markCount! > count ? markCount! : count;

  /// Lowest confidence among the detections that make up [count]
  /// (or the classifier's confidence that there are none).
  final double confidence;

  /// Builds a feature count from JSON. Missing numbers become 0.
  factory FeatureDetectionModel.fromJson(Map<String, dynamic> json) =>
      FeatureDetectionModel(
        count: _i(json['count']) ?? 0,
        confidence: _d(json['confidence']),
        uncertainCount: _i(json['uncertain_count']) ?? 0,
        markCount: _i(json['mark_count']),
      );

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'count': count,
        'confidence': confidence,
        'uncertain_count': uncertainCount,
        'mark_count': markCount,
      };
}

/// The year printed on the note, as read by the detector and OCR.
class PrintedYearModel {
  const PrintedYearModel({
    required this.detected,
    required this.confidence,
    this.value,
  });

  /// True when a year was found.
  final bool detected;

  /// The year text (for example "2019"). Null when none was read.
  final String? value;

  /// Detection confidence, 0..1.
  final double confidence;

  /// Builds the year result from JSON.
  factory PrintedYearModel.fromJson(Map<String, dynamic> json) =>
      PrintedYearModel(
        detected: json['detected'] == true,
        value: json['value']?.toString(),
        confidence: _d(json['confidence']),
      );

  /// Converts to JSON.
  Map<String, dynamic> toJson() =>
      {'detected': detected, 'value': value, 'confidence': confidence};
}

/// One serial number region as read by OCR.
class SerialReadModel {
  const SerialReadModel({
    required this.text,
    required this.confidence,
    this.ocrReads = const [],
  });

  /// The serial number text chosen from the OCR reads.
  final String text;

  /// Detection confidence for this region, 0..1.
  final double confidence;

  /// Raw OCR text from each pass over this region, for diagnostics.
  final List<String> ocrReads;

  /// Builds a serial read from JSON. Missing text becomes an empty string.
  factory SerialReadModel.fromJson(Map<String, dynamic> json) =>
      SerialReadModel(
        text: (json['text'] ?? '').toString(),
        confidence: _d(json['confidence']),
        ocrReads: [
          for (final r in (json['ocr_reads'] as List? ?? const [])) '$r',
        ],
      );

  /// Converts to JSON.
  Map<String, dynamic> toJson() =>
      {'text': text, 'confidence': confidence, 'ocr_reads': ocrReads};
}

/// Everything the detector found on ONE side (front or back) of the note.
class SideDetectionModel {
  const SideDetectionModel({
    required this.quality,
    required this.denomination,
    required this.denominationConfidence,
    this.sbpSeals,
    this.securityThreads,
    this.securityLines,
    this.securityDots,
    this.printedYear,
    this.serialNumbers = const [],
  });

  /// Photo quality (blur, glare, brightness) for this side.
  final ImageQualityModel quality;

  /// Note value in rupees read on this side. Null if not read.
  final int? denomination;

  /// Confidence for [denomination], 0..1.
  final double denominationConfidence;

  /// SBP seals found. `null` when no detector for this feature is installed.
  /// The same rule applies to the three fields below.
  final FeatureDetectionModel? sbpSeals;

  /// Security thread count.
  final FeatureDetectionModel? securityThreads;

  /// Security line count / security dot count (depends on the denomination).
  final FeatureDetectionModel? securityLines;
  final FeatureDetectionModel? securityDots;

  /// Printed year result. Null when not checked on this side.
  final PrintedYearModel? printedYear;

  /// Serial numbers read on this side (the front has two regions).
  final List<SerialReadModel> serialNumbers;

  /// Reads one optional feature entry. Returns null if it is not a map.
  static FeatureDetectionModel? _feature(Object? json) =>
      json is Map<String, dynamic> ? FeatureDetectionModel.fromJson(json) : null;

  /// Builds one side from JSON. Missing features stay null.
  factory SideDetectionModel.fromJson(Map<String, dynamic> json) =>
      SideDetectionModel(
        quality: ImageQualityModel.fromJson(
          (json['quality'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        denomination: _i(json['denomination']),
        denominationConfidence: _d(json['denomination_confidence']),
        sbpSeals: _feature(json['sbp_seals']),
        securityThreads: _feature(json['security_threads']),
        securityLines: _feature(json['security_lines']),
        securityDots: _feature(json['security_dots']),
        printedYear: json['printed_year'] is Map<String, dynamic>
            ? PrintedYearModel.fromJson(json['printed_year'])
            : null,
        // Keep only entries that are valid maps.
        serialNumbers: [
          for (final s in (json['serial_numbers'] as List? ?? const []))
            if (s is Map<String, dynamic>) SerialReadModel.fromJson(s),
        ],
      );

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'quality': quality.toJson(),
        'denomination': denomination,
        'denomination_confidence': denominationConfidence,
        'sbp_seals': sbpSeals?.toJson(),
        'security_threads': securityThreads?.toJson(),
        'security_lines': securityLines?.toJson(),
        'security_dots': securityDots?.toJson(),
        'printed_year': printedYear?.toJson(),
        'serial_numbers': serialNumbers.map((s) => s.toJson()).toList(),
      };
}

/// Result of the surface anomaly model (MobileNetV3).
class AnomalyModel {
  const AnomalyModel({
    required this.anomalyScore,
    this.threshold = 0.5,
    this.model = 'MobileNetV3',
    this.frontScore,
    this.backScore,
  });

  /// 0 = perfectly consistent surface, 1 = strong visual anomaly.
  /// The worse of the two sides when both were scored.
  final double anomalyScore;

  /// Score for the front side only. Null if the front was not scored.
  final double? frontScore;

  /// Score for the back side only. Null if the back was not scored.
  final double? backScore;

  /// Scores at or above this are treated as a strong anomaly.
  final double threshold;

  /// Name of the model that produced the score.
  final String model;

  /// True when [anomalyScore] reaches the [threshold].
  bool get isStrongAnomaly => anomalyScore >= threshold;

  /// Builds the anomaly result from JSON (threshold defaults to 0.5).
  factory AnomalyModel.fromJson(Map<String, dynamic> json) => AnomalyModel(
        anomalyScore: _d(json['anomaly_score']),
        threshold: _d(json['threshold'], 0.5),
        model: (json['model'] ?? 'MobileNetV3').toString(),
        frontScore: (json['front_score'] as num?)?.toDouble(),
        backScore: (json['back_score'] as num?)?.toDouble(),
      );

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'anomaly_score': anomalyScore,
        'threshold': threshold,
        'model': model,
        'front_score': frontScore,
        'back_score': backScore,
      };
}

/// Root payload of the verification endpoint.
class NoteAnalysisModel {
  const NoteAnalysisModel({
    required this.isBanknote,
    required this.banknoteConfidence,
    this.front,
    this.back,
    this.anomaly,
    this.anomalySkipReason,
    this.counterfeitCnn,
    this.smallCnn,
    this.smallCnnSkipReason,
    this.microprint,
    this.monument,
    this.portrait,
    this.rs5000OnlyReason,
    this.rejectionKind,
    this.rejectionReasons = const [],
    this.timingsMs = const {},
    this.detections = const {},
  });

  /// False when the images were judged not to be a banknote.
  final bool isBanknote;

  /// Confidence that the image is a banknote, 0..1.
  final double banknoteConfidence;

  /// Findings for the front side. Null when not analysed.
  final SideDetectionModel? front;

  /// Findings for the back side. Null when not analysed.
  final SideDetectionModel? back;

  /// Surface anomaly result. Null when the model did not run.
  final AnomalyModel? anomaly;

  /// Why the anomaly model did not run (e.g. unsupported denomination).
  final String? anomalySkipReason;

  /// Rs 5,000 genuine/counterfeit classifier output (second CNN).
  final CounterfeitCnnModel? counterfeitCnn;

  /// MobileNetV3-Small genuine/fake output for Rs 10–1,000 (P(fake) per
  /// side, stored in the same shape as [counterfeitCnn]).
  final CounterfeitCnnModel? smallCnn;

  /// Set when the Rs 10–1,000 classifier should have run but could not
  /// (model missing or failed). The engine then reports UNABLE TO VERIFY
  /// instead of silently treating the note as genuine.
  final String? smallCnnSkipReason;

  /// Back-side monument check. Null when the analysis did not reach it.
  final MonumentResultModel? monument;

  /// Front-side Quaid-e-Azam portrait check. Null when the analysis did not reach it.
  final PortraitResultModel? portrait;

  /// Edge microprint (Rs 5,000 only for now). Null when not read.
  final MicroprintModel? microprint;

  /// Set when the note is not Rs 5,000: both Rs 5,000-only CNN checks are
  /// then "not applicable" rather than skipped.
  final String? rs5000OnlyReason;

  /// 'paper' (A4 / page / printout) or 'no_note'. Null when accepted.
  final String? rejectionKind;

  /// Why the image was judged not to be a banknote.
  final List<String> rejectionReasons;

  /// Stage latencies on the device, for performance checks.
  /// Key = stage name, value = milliseconds.
  final Map<String, int> timingsMs;

  /// Post-NMS YOLO boxes per side ("front"/"back"), for the on-screen
  /// overlay and parity checks with Colab.
  final Map<String, SideDetectionsModel> detections;

  /// Same analysis with a new microprint reading (close-up capture).
  NoteAnalysisModel withMicroprint(MicroprintModel value) => NoteAnalysisModel(
        isBanknote: isBanknote,
        banknoteConfidence: banknoteConfidence,
        front: front,
        back: back,
        anomaly: anomaly,
        anomalySkipReason: anomalySkipReason,
        counterfeitCnn: counterfeitCnn,
        smallCnn: smallCnn,
        smallCnnSkipReason: smallCnnSkipReason,
        microprint: value,
        monument: monument,
        portrait: portrait,
        rs5000OnlyReason: rs5000OnlyReason,
        rejectionKind: rejectionKind,
        rejectionReasons: rejectionReasons,
        timingsMs: timingsMs,
        detections: detections,
      );

  /// Builds the full analysis from JSON. Every part is optional except the
  /// banknote flag, so missing parts simply become null.
  factory NoteAnalysisModel.fromJson(Map<String, dynamic> json) {
    // Helper: returns the value as a typed map, or null if it is not a map.
    Map<String, dynamic>? m(Object? v) =>
        v is Map ? v.cast<String, dynamic>() : null;
    return NoteAnalysisModel(
      isBanknote: json['is_banknote'] == true,
      banknoteConfidence: _d(json['banknote_confidence']),
      front: m(json['front']) == null
          ? null
          : SideDetectionModel.fromJson(m(json['front'])!),
      back: m(json['back']) == null
          ? null
          : SideDetectionModel.fromJson(m(json['back'])!),
      anomaly: m(json['anomaly']) == null
          ? null
          : AnomalyModel.fromJson(m(json['anomaly'])!),
      anomalySkipReason: json['anomaly_skip_reason'] as String?,
      counterfeitCnn: m(json['counterfeit_cnn']) == null
          ? null
          : CounterfeitCnnModel.fromJson(m(json['counterfeit_cnn'])!),
      smallCnn: m(json['small_cnn']) == null
          ? null
          : CounterfeitCnnModel.fromJson(m(json['small_cnn'])!),
      smallCnnSkipReason: json['small_cnn_skip_reason'] as String?,
      monument: m(json['monument']) == null
          ? null
          : MonumentResultModel.fromJson(m(json['monument'])!),
      portrait: m(json['portrait']) == null
          ? null
          : PortraitResultModel.fromJson(m(json['portrait'])!),
      microprint: m(json['microprint']) == null
          ? null
          : MicroprintModel.fromJson(m(json['microprint'])!),
      rs5000OnlyReason: json['rs5000_only_reason'] as String?,
      rejectionKind: json['rejection_kind'] as String?,
      rejectionReasons: [
        for (final r in (json['rejection_reasons'] as List? ?? const []))
          r.toString(),
      ],
      // Stage name -> milliseconds.
      timingsMs: {
        for (final e in ((json['timings_ms'] as Map?) ?? const {}).entries)
          '${e.key}': (e.value as num).toInt(),
      },
      // Side name ("front"/"back") -> its detection boxes.
      detections: {
        for (final e in ((json['detections'] as Map?) ?? const {}).entries)
          '${e.key}': SideDetectionsModel.fromJson(
              (e.value as Map).cast<String, dynamic>()),
      },
    );
  }

  /// Converts the whole analysis to JSON (same keys that fromJson reads).
  Map<String, dynamic> toJson() => {
        'is_banknote': isBanknote,
        'banknote_confidence': banknoteConfidence,
        'front': front?.toJson(),
        'back': back?.toJson(),
        'anomaly': anomaly?.toJson(),
        'anomaly_skip_reason': anomalySkipReason,
        'counterfeit_cnn': counterfeitCnn?.toJson(),
        'small_cnn': smallCnn?.toJson(),
        'small_cnn_skip_reason': smallCnnSkipReason,
        'microprint': microprint?.toJson(),
        'monument': monument?.toJson(),
        'portrait': portrait?.toJson(),
        'rs5000_only_reason': rs5000OnlyReason,
        'rejection_kind': rejectionKind,
        'rejection_reasons': rejectionReasons,
        'timings_ms': timingsMs,
        'detections': {
          for (final e in detections.entries) e.key: e.value.toJson(),
        },
      };
}

/// One YOLO box, with coordinates as fractions (0–1) of the image.
class DetectionBoxModel {
  const DetectionBoxModel({
    required this.classId,
    required this.label,
    required this.score,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Number of the YOLO class this box belongs to.
  final int classId;

  /// Class name (for example a seal or thread label).
  final String label;

  /// Detection confidence, 0..1.
  final double score;

  /// Box edges as fractions (0..1) of the image width / height.
  final double left, top, right, bottom;

  /// Builds a box from JSON. 'box' is a list: [left, top, right, bottom].
  factory DetectionBoxModel.fromJson(Map<String, dynamic> json) {
    final b = (json['box'] as List).map((v) => (v as num).toDouble()).toList();
    return DetectionBoxModel(
      classId: _i(json['class_id']) ?? 0,
      label: json['label'] as String,
      score: _d(json['score']),
      left: b[0],
      top: b[1],
      right: b[2],
      bottom: b[3],
    );
  }

  /// Converts to JSON ('box' is written as [left, top, right, bottom]).
  Map<String, dynamic> toJson() => {
        'class_id': classId,
        'label': label,
        'score': score,
        'box': [left, top, right, bottom],
      };
}

/// All boxes for one side plus the analysed image size (for aspect ratio).
class SideDetectionsModel {
  const SideDetectionsModel({
    required this.width,
    required this.height,
    required this.boxes,
  });

  /// Analysed image width in pixels.
  final int width;

  /// Analysed image height in pixels.
  final int height;

  /// All detected boxes on this side.
  final List<DetectionBoxModel> boxes;

  /// Builds from JSON. Missing size defaults to 1 so it never divides by 0.
  factory SideDetectionsModel.fromJson(Map<String, dynamic> json) =>
      SideDetectionsModel(
        width: _i(json['width']) ?? 1,
        height: _i(json['height']) ?? 1,
        boxes: [
          for (final b in (json['boxes'] as List? ?? const []))
            DetectionBoxModel.fromJson((b as Map).cast<String, dynamic>()),
        ],
      );

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'boxes': boxes.map((b) => b.toJson()).toList(),
      };
}

/// Output of the genuine/counterfeit MobileNetV3 classifier (Rs 5,000 uses
/// the Large model; the Small model for Rs 10-1,000 uses the same shape).
class CounterfeitCnnModel {
  const CounterfeitCnnModel({
    required this.frontCounterfeit,
    required this.backCounterfeit,
    this.threshold = 0.5,
    this.model = 'MobileNetV3-Large',
  });

  /// P(counterfeit) for each side (softmax over [counterfeit, genuine]).
  final double frontCounterfeit;
  final double backCounterfeit;

  /// A probability at or above this flags the note as counterfeit.
  final double threshold;

  /// Name of the model that produced the output.
  final String model;

  /// The worse side decides, like the alteration CNN.
  double get counterfeitProbability =>
      frontCounterfeit > backCounterfeit ? frontCounterfeit : backCounterfeit;

  /// True when the worse side reaches the [threshold].
  bool get flagsCounterfeit => counterfeitProbability >= threshold;

  /// Builds from JSON (threshold defaults to 0.5).
  factory CounterfeitCnnModel.fromJson(Map<String, dynamic> json) =>
      CounterfeitCnnModel(
        frontCounterfeit: _d(json['front_counterfeit']),
        backCounterfeit: _d(json['back_counterfeit']),
        threshold: _d(json['threshold'], 0.5),
        model: (json['model'] ?? 'MobileNetV3-Large').toString(),
      );

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'front_counterfeit': frontCounterfeit,
        'back_counterfeit': backCounterfeit,
        'threshold': threshold,
        'model': model,
      };
}

/// Edge microprint reading: how often the expected denomination appears in
/// the tiny repeated text along the note's border.
class MicroprintModel {
  const MicroprintModel({
    required this.expected,
    required this.occurrences,
    required this.source,
    this.conflicting,
    this.conflictingOccurrences = 0,
    this.sample = '',
  });

  /// Denomination the border text must repeat (from YOLO).
  final int expected;

  /// Times the expected number was read.
  final int occurrences;

  /// A different denomination clearly repeated instead, if any.
  final int? conflicting;

  /// Times the [conflicting] number was read.
  final int conflictingOccurrences;

  /// 'scan' (border strips of the normal capture) or 'close-up'.
  final String source;

  /// Short excerpt of what OCR read, for the details row.
  final String sample;

  /// Builds from JSON. Missing counts become 0, missing source 'scan'.
  factory MicroprintModel.fromJson(Map<String, dynamic> json) => MicroprintModel(
        expected: _i(json['expected']) ?? 0,
        occurrences: _i(json['occurrences']) ?? 0,
        source: (json['source'] ?? 'scan').toString(),
        conflicting: _i(json['conflicting']),
        conflictingOccurrences: _i(json['conflicting_occurrences']) ?? 0,
        sample: (json['sample'] ?? '').toString(),
      );

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'expected': expected,
        'occurrences': occurrences,
        'source': source,
        'conflicting': conflicting,
        'conflicting_occurrences': conflictingOccurrences,
        'sample': sample,
      };
}

/// Back-side monument classifier output (Teachable Machine / MobileNet).
class MonumentResultModel {
  const MonumentResultModel({
    required this.modelAvailable,
    this.label,
    this.confidence = 0,
    this.verified = false,
    this.knownDenominations = const [],
  });

  /// A "model not installed" result: no label, no confidence.
  const MonumentResultModel.notInstalled() : this(modelAvailable: false);

  /// False when the monument model file is not in the app.
  final bool modelAvailable;

  /// Predicted class, e.g. 'monument_100' or 'invalid'.
  final String? label;

  /// Confidence of the predicted [label], 0..1.
  final double confidence;

  /// True only when the training pipeline measured ≥ 90% accuracy per class
  /// on held-out photos. Unverified models never make a note FAKE.
  final bool verified;

  /// Denominations the model was trained on (others cannot be checked).
  final List<int> knownDenominations;

  /// Denomination whose monument was recognised; null for 'invalid'.
  int? get denomination {
    // Labels look like 'monument_500'; pull out the number part.
    final m = RegExp(r'^monument_(\d+)$').firstMatch(label ?? '');
    return m == null ? null : int.parse(m.group(1)!);
  }

  /// Builds from JSON. Unreadable denominations in the list are skipped.
  factory MonumentResultModel.fromJson(Map<String, dynamic> json) =>
      MonumentResultModel(
        modelAvailable: json['model_available'] == true,
        label: json['label'] as String?,
        confidence: _d(json['confidence']),
        verified: json['verified'] == true,
        knownDenominations: [
          for (final v in (json['known_denominations'] as List? ?? const []))
            if (_i(v) != null) _i(v)!,
        ],
      );

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'model_available': modelAvailable,
        'label': label,
        'confidence': confidence,
        'verified': verified,
        'known_denominations': knownDenominations,
      };
}

/// Front-side Quaid-e-Azam portrait classifier output (same shape as
/// [MonumentResultModel]): labels are 'portrait_<value>' or 'invalid'.
class PortraitResultModel {
  const PortraitResultModel({
    required this.modelAvailable,
    this.label,
    this.confidence = 0,
    this.verified = false,
    this.knownDenominations = const [],
  });

  /// A "model not installed" result: no label, no confidence.
  const PortraitResultModel.notInstalled() : this(modelAvailable: false);

  /// False when the portrait model file is not in the app.
  final bool modelAvailable;

  /// Predicted class, e.g. 'portrait_100' or 'invalid'.
  final String? label;

  /// Confidence of the predicted [label], 0..1.
  final double confidence;

  /// True only when the training pipeline measured a good accuracy per class
  /// on held-out photos. Unverified models never make a note FAKE.
  final bool verified;

  /// Denominations the model was trained on (others cannot be checked).
  final List<int> knownDenominations;

  /// Denomination whose portrait design was recognised; null for 'invalid'.
  int? get denomination {
    final m = RegExp(r'^portrait_(\d+)$').firstMatch(label ?? '');
    return m == null ? null : int.parse(m.group(1)!);
  }

  /// Builds from JSON. Unreadable denominations in the list are skipped.
  factory PortraitResultModel.fromJson(Map<String, dynamic> json) =>
      PortraitResultModel(
        modelAvailable: json['model_available'] == true,
        label: json['label'] as String?,
        confidence: _d(json['confidence']),
        verified: json['verified'] == true,
        knownDenominations: [
          for (final v in (json['known_denominations'] as List? ?? const []))
            if (_i(v) != null) _i(v)!,
        ],
      );

  /// Converts to JSON.
  Map<String, dynamic> toJson() => {
        'model_available': modelAvailable,
        'label': label,
        'confidence': confidence,
        'verified': verified,
        'known_denominations': knownDenominations,
      };
}
