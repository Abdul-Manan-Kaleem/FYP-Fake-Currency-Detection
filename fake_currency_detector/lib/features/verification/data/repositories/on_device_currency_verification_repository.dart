import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../../core/network/verification_exception.dart';
import '../../domain/note_image_input.dart';
import '../../domain/currency_rules.dart';
import '../../domain/currency_verification_repository.dart';
import '../../domain/side_classifier.dart';
import '../models/note_analysis_model.dart';
import '../on_device/image_preprocessor.dart';
import '../on_device/microprint_reader.dart';
import '../on_device/mobilenetv3_small_classifier.dart';
import '../on_device/monument_classifier.dart';
import '../on_device/note_presence.dart';
import '../on_device/note_side_classifier.dart';
import '../on_device/partial_note_detector.dart';
import '../on_device/pkr5000_counterfeit_classifier.dart';
import '../on_device/portrait_classifier.dart';
import '../on_device/note_text_parser.dart';
import '../on_device/rs5000_anomaly_classifier.dart';
import '../on_device/yolo_decoder.dart';
import '../on_device/yolo_detector.dart';

/// ON-DEVICE VERIFICATION PIPELINE (the "collector of evidence")
///
/// PURPOSE
/// This is the real scanner of the app. It runs entirely on the phone.
/// It takes the photos of the front and back of a banknote and produces a
/// [NoteAnalysisModel]: a bundle of raw EVIDENCE (boxes, OCR text, scores).
/// It does NOT decide real or fake. That is the job of the VerificationEngine
/// (domain/verification_engine.dart), which reads this evidence and applies
/// the rules and the weighted score.
///
/// Each model keeps its own role:
/// - YOLO11s: is it a note, which denomination, and where/how many security
///   features (seals, thread, lines, dots, serial regions, printed year)
/// - ML Kit OCR: reads the text inside the YOLO serial-number / year boxes
/// - Rs 5,000 CNNs: alteration score and genuine/counterfeit score, Rs 5,000
///   only, supporting evidence
/// - Monument classifier: checks the picture on the back
///
/// HOW IT FITS
///   capture screen -> checkSide() / scanSide() right after each photo
///   -> analyzeBanknote() when both sides exist -> NoteAnalysisModel
///   -> VerificationEngine.evaluate() -> result screen.
/// Another class, ApiCurrencyVerificationRepository, is a server-based
/// alternative with the same interface. This on-device one is the one used.
///
/// MAIN SECTIONS OF THIS FILE
///  1. [SideScan]: result of preparing and running YOLO11s on ONE photo.
///  2. [OnDeviceCurrencyVerificationRepository]:
///     a. scanSide / _scan: prepare image + YOLO11s + monument (cached).
///     b. checkSide: quick "which side is this?" check at capture time.
///     c. analyzeBanknote: the full pipeline, in these steps:
///        1.  Find the note box on each side.
///        1b. Shape gate (half or partial note).
///        1c. Presence gate (is there really a note?).
///        2.  OCR of two serial numbers and the printed year.
///        2a. Count the marks inside the lines/dots boxes.
///        2b. Rs 5,000 only: full-resolution prep and edge microprint.
///        3.  Rs 5,000 CNNs (or the small CNN, currently switched off).
///        4.  Build the [NoteAnalysisModel], including the monument result.
///  3. Static helpers: box conversion, counting, OCR, sorting by confidence.

/// Image preparation + YOLO11s for one captured side. Computed once per
/// photo (right after capture) and reused by the side check and analysis.
class SideScan {
  const SideScan({
    required this.prepared,
    required this.detections,
    required this.classMax,
    required this.prepareMs,
    required this.yoloMs,
    this.monument,
    this.monumentModelAvailable = false,
    this.monumentVerified = false,
    this.monumentKnown = const [],
  });

  /// The resized working copy of the photo (pixels, YOLO input, CNN input,
  /// quality report, letterbox info).
  final PreparedImage prepared;

  /// Post-NMS boxes in working-image pixels.
  final List<YoloDetection> detections;

  /// Highest score each YOLO class reached anywhere in the image, even if it
  /// never made a box. Used to spot "faintly seen" features.
  final List<double> classMax;

  /// Time spent preparing the image, in milliseconds (for timing logs).
  final int prepareMs;

  /// Time spent running YOLO11s, in milliseconds (for timing logs).
  final int yoloMs;

  /// Back-side monument prediction (null when the model is not installed).
  final MonumentPrediction? monument;

  /// True if the monument model file is installed and loaded.
  final bool monumentModelAvailable;

  /// True if the monument model is a finished ("verified") model. A
  /// preliminary model is only reported and never trusted for decisions.
  final bool monumentVerified;

  /// Denominations the monument model was trained on.
  final List<int> monumentKnown;
}

/// The on-device scanner. Implements two roles:
///  * [CurrencyVerificationRepository]: [analyzeBanknote] gives evidence for
///    the whole note.
///  * [SideClassifier]: [checkSide] tells which side a photo shows.
/// Models are loaded lazily on first use and kept for later scans.
class OnDeviceCurrencyVerificationRepository
    implements CurrencyVerificationRepository, SideClassifier {
  /// [clock] can be replaced in tests. It is used to reject printed years
  /// that are in the future.
  OnDeviceCurrencyVerificationRepository({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  // Lazy model holders: null until first use, then the loaded model future.
  // ??= means "load only if not loaded yet".

  /// YOLO11s detector (note, denomination, security features).
  Future<YoloDetector>? _yolo;

  /// Rs 5,000 alteration CNN.
  Future<Rs5000AnomalyClassifier>? _cnn;

  /// Rs 5,000 genuine/counterfeit CNN.
  Future<Pkr5000CounterfeitClassifier>? _counterfeitCnn;

  /// MobileNetV3-Small genuine/fake CNN for Rs 10-1,000. Only loaded when
  /// kSmallCnnEnabled is true (it is false now, so this stays null).
  Future<MobileNetV3SmallClassifier>? _smallCnn;

  /// Back-side monument classifier. Resolves to null if not installed.
  Future<MonumentClassifier?>? _monument;

  /// Front-side Quaid-e-Azam portrait classifier. Resolves to null if not installed.
  Future<PortraitClassifier?>? _portrait;

  /// Face-level portrait classifier (genuine Quaid-e-Azam vs changed). Null if not installed.
  Future<PortraitClassifier?>? _portraitFace;

  /// Scans by image path. A path is a unique captured file, so a retake is a
  /// new entry; old entries are dropped on [forget].
  final Map<String, Future<SideScan>> _scans = {};

  /// Prepares [path] and runs YOLO11s once; later calls reuse the result.
  /// Called right after each photo is taken, so the work is usually done by
  /// the time the user asks for the final analysis.
  Future<SideScan> scanSide(String path) {
    final cached = _scans[path];
    if (cached != null) return cached;
    final scan = _scan(path);
    _scans[path] = scan;
    // A failed scan must be retryable, so drop it from the cache.
    scan.then((_) {}, onError: (Object _) {
      _scans.remove(path);
    }).ignore();
    return scan;
  }

  /// Does the real work for one photo (no caching, see [scanSide]).
  /// Steps: 1) prepare the image, 2) run YOLO11s, 3) run the optional
  /// monument model, 4) convert boxes to image pixels and return a
  /// [SideScan].
  Future<SideScan> _scan(String path) async {
    final sw = Stopwatch()..start();
    // 1. Resize/prepare the photo and measure its quality.
    final prepared = await ImagePreprocessor.prepare(path);
    final prepareMs = sw.elapsedMilliseconds;
    // 2. YOLO11s finds the note and its security features.
    final yolo = await (_yolo ??= _load(YoloDetector.load, 'YOLO11s'));
    final (raw, classMax) = await yolo.detect(prepared.yoloInput);
    final yoloMs = sw.elapsedMilliseconds - prepareMs;

    // 3. Optional monument model (Teachable Machine); ~tens of ms. A failure
    //    here is only logged; it never stops the scan.
    final monumentModel = await (_monument ??= MonumentClassifier.tryLoad());
    MonumentPrediction? monument;
    if (monumentModel != null) {
      try {
        monument = await monumentModel.classify(prepared.pixels);
        debugPrint('Monument $path → ${monument.label} '
            '${monument.confidence.toStringAsFixed(2)}');
      } on Object catch (e) {
        debugPrint('Monument classification failed: $e');
      }
    }
    return SideScan(
      prepared: prepared,
      detections: _toImage(raw, prepared.letterbox),
      classMax: classMax,
      prepareMs: prepareMs,
      yoloMs: yoloMs,
      monument: monument,
      monumentModelAvailable: monumentModel != null,
      monumentVerified: monumentModel?.verified ?? false,
      monumentKnown: monumentModel?.knownDenominations ?? const [],
    );
  }

  /// Releases cached scans that are no longer needed.
  void forget(Iterable<String> paths) => paths.forEach(_scans.remove);

  /// Quick check done at capture time: which side does this photo show
  /// (front, back, unknown), which denomination does it look like, and does
  /// it look like a note at all? Reuses the cached [SideScan], so it is cheap.
  ///
  /// The monument prediction is only trusted when the monument model is
  /// verified (finished). Input: [imagePath]. Output: a [SideCheck].
  @override
  Future<SideCheck> checkSide(String imagePath) async {
    final scan = await scanSide(imagePath);
    final trusted = scan.monumentVerified ? scan.monument : null;
    final side = NoteSideRules.classify(scan.detections, trusted);
    final note = _bestNote(scan.detections);
    final m = trusted;
    final check = SideCheck(
      side: side,
      noteDenomination:
          note != null && note.score >= confirmThreshold ? note.cls.denomination : null,
      monumentDenomination:
          m != null && m.confidence >= NoteSideRules.monumentConfidence
              ? m.denomination
              : null,
      // A confident monument also proves it is a note, even if YOLO found
      // no seal on a worn back.
      looksLikeNote: NotePresence.looksLikeNote(scan.detections) ||
          (m != null &&
              m.denomination != null &&
              m.confidence >= NoteSideRules.monumentConfidence),
    );
    debugPrint('Side check $imagePath → $side, note ${check.noteDenomination}, '
        'monument ${check.monumentDenomination}');
    return check;
  }

  /// Below this a YOLO box is "seen but unconfirmed" and never counts.
  static const double confirmThreshold = CurrencyRules.minDetectionConfidence;

  /// Label stored on the final result so the app knows where it came from.
  @override
  String get sourceLabel => 'on-device';

  /// Loads a model and turns any error into a [VerificationException] with
  /// a readable message. [what] is the model name used in that message.
  Future<T> _load<T>(Future<T> Function() loader, String what) =>
      loader().catchError((Object e) => throw VerificationException(
            VerificationErrorKind.unknown,
            'Could not load the $what model: $e',
          ));

  /// THE FULL PIPELINE. Collects all evidence for one note.
  ///
  /// Inputs: [front] and [back] photos. Output: a [NoteAnalysisModel] with
  /// either (a) a rejection (not a note / partial note) or (b) the evidence
  /// for both sides plus classifier results. It never gives a verdict; the
  /// VerificationEngine does that. Timings of each stage are stored in
  /// `timingsMs` for debugging.
  @override
  Future<NoteAnalysisModel> analyzeBanknote({
    required NoteImageInput front,
    required NoteImageInput back,
  }) async {
    final total = Stopwatch()..start();
    final timings = <String, int>{};
    int lap(Stopwatch s) => (s..stop()).elapsedMilliseconds;

    // Temporary folder for cropped images; deleted in the `finally` at the end.
    final dir = await Directory.systemTemp.createTemp('fcd_');
    try {
      // ---- Step 0: get both side scans ----
      // Usually already finished: each side is scanned right after capture.
      var sw = Stopwatch()..start();
      final (fs, bs) = await (scanSide(front.path), scanSide(back.path))
          .wait
          .catchError((Object e) => throw VerificationException(
                VerificationErrorKind.unknown,
                'Could not read the captured image: $e',
              ));
      timings['scan_wait'] = lap(sw);
      timings['prep_front'] = fs.prepareMs;
      timings['yolo_front'] = fs.yoloMs;
      timings['prep_back'] = bs.prepareMs;
      timings['yolo_back'] = bs.yoloMs;
      final f = fs.prepared, b = bs.prepared;
      final frontDets = fs.detections, backDets = bs.detections;
      final frontMax = fs.classMax, backMax = bs.classMax;
      debugPrint('YOLO class max front: ${_fmtMax(frontMax)}');
      debugPrint('YOLO class max back:  ${_fmtMax(backMax)}');

      final detections = {
        'front': _sideDetections(frontDets, f),
        'back': _sideDetections(backDets, b),
      };
      // Same "id:label score [x1, y1, x2, y2]" format as tools/yolo_parity.py.
      debugPrint('YOLO front (${f.width}x${f.height}): $frontDets');
      debugPrint('YOLO back  (${b.width}x${b.height}): $backDets');

      // ---- Gate: note box, shape and presence ----
      // 1. Is there a banknote on each side at all?
      final frontNote = _bestNote(frontDets);
      final backNote = _bestNote(backDets);

      // The old A4/paper-shape heuristic was removed: it misfired on real
      // notes. Non-notes (pages, printouts) are rejected below by YOLO
      // feature evidence (NotePresence) instead.
      debugPrint('Image shape: front ${f.aspectRatio.toStringAsFixed(2)} : 1, '
          'back ${b.aspectRatio.toStringAsFixed(2)} : 1');

      // 1b. Half / partial note: the image shape must match the shape of the
      //     note YOLO sees (all notes are 65 mm tall, 8 mm longer per step).
      final partial = [
        if (frontNote != null)
          ?PartialNoteDetector.rejection(
            side: 'FRONT',
            aspectRatio: f.aspectRatio,
            denomination: frontNote.cls.denomination,
            noteScore: frontNote.score,
          ),
        if (backNote != null)
          ?PartialNoteDetector.rejection(
            side: 'BACK',
            aspectRatio: b.aspectRatio,
            denomination: backNote.cls.denomination,
            noteScore: backNote.score,
          ),
      ];
      if (partial.isNotEmpty) {
        timings['total'] = lap(total);
        return NoteAnalysisModel(
          isBanknote: false,
          banknoteConfidence: 0,
          rejectionKind: 'partial',
          rejectionReasons: [...partial, ...PartialNoteDetector.guidance],
          timingsMs: timings,
          detections: detections,
        );
      }

      // 1c. Presence gate: a real note must show enough YOLO feature
      //     evidence on each side. If not, return "not a banknote" now.
      final reasons = [
        ?NotePresence.rejection(frontDets, isFront: true),
        ?NotePresence.rejection(backDets, isFront: false),
      ];
      if (reasons.isNotEmpty) {
        timings['total'] = lap(total);
        return NoteAnalysisModel(
          isBanknote: false,
          banknoteConfidence: math.max(frontNote?.score ?? 0, backNote?.score ?? 0),
          rejectionKind: 'no_note',
          rejectionReasons: reasons,
          timingsMs: timings,
          detections: detections,
        );
      }

      // ---- Step 2: OCR of serial numbers and printed year ----
      // 2. OCR inside YOLO's serial-number and printed-year boxes.
      sw = Stopwatch()..start();
      final serialBoxes = _confirmed(frontDets, YoloClass.serialNumber);
      final serialUncertain = _uncertain(frontDets, YoloClass.serialNumber);
      final yearBox = _confirmed(frontDets, YoloClass.printedYear).firstOrNull;
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      late final List<SerialReadModel> serials;
      String? yearValue;
      try {
        // OCR at most the two expected serial regions, then the year.
        final toRead = serialBoxes.take(CurrencyRules.frontSerialRegions).toList();
        final ocrBoxes = [for (final d in toRead) d.box, ?yearBox?.box];
        final crops = await ImagePreprocessor.crops(f.pixels, ocrBoxes, dir.path);

        Future<List<OcrLine>> read(String path) async {
          try {
            return await _ocr(recognizer, path);
          } on Object catch (e) {
            // An unreadable crop means "could not read", which the engine
            // reports as UNABLE TO VERIFY. It must not abort the analysis.
            debugPrint('OCR failed on $path: $e');
            return const [];
          }
        }

        // Two OCR passes per serial region (plain + enhanced crop).
        final passes = <List<SerialRead>>[];
        for (final (plain, enhanced) in crops.take(toRead.length)) {
          passes.add([
            NoteTextParser.serialFromCrop(await read(plain)),
            NoteTextParser.serialFromCrop(await read(enhanced)),
          ]);
        }
        for (final (i, p) in passes.indexed) {
          debugPrint('OCR serial #${i + 1}: '
              '${p.map((r) => '"${r.raw}" → "${r.text}"').join(' | ')}');
        }

        // Wrap one chosen read, plus the raw text of both passes, for the
        // result screen.
        SerialReadModel model(SerialRead r, List<SerialRead> pass) =>
            SerialReadModel(
              text: r.text,
              confidence: r.confidence,
              ocrReads: [for (final x in pass) x.raw],
            );

        // With two regions, reconcile the passes of both serials together
        // (the two serials should be equal, so each helps fix the other).
        // Otherwise take the first non-empty read of each region.
        if (passes.length == 2) {
          final (a, b) = NoteTextParser.reconcile(passes[0], passes[1]);
          serials = [model(a, passes[0]), model(b, passes[1])];
        } else {
          serials = [
            for (final p in passes)
              model(p.firstWhere((r) => !r.isEmpty, orElse: () => p.first), p),
          ];
        }
        // Extra confirmed regions still count, so the engine sees "found 3".
        serials.addAll([
          for (final d in serialBoxes.skip(toRead.length))
            SerialReadModel(text: '(extra region)', confidence: d.score),
        ]);

        if (yearBox != null) {
          final (plain, enhanced) = crops.last;
          yearValue = NoteTextParser.yearFromCrop(await read(plain),
                  maxYear: _clock().year) ??
              NoteTextParser.yearFromCrop(await read(enhanced),
                  maxYear: _clock().year);
        }
        debugPrint('OCR serials: ${serials.map((s) => s.text)} year: $yearValue');
      } on Object catch (e) {
        throw VerificationException(
          VerificationErrorKind.unknown,
          'On-device text recognition failed: $e',
        );
      } finally {
        await recognizer.close();
      }
      timings['ocr'] = lap(sw);

      // Too few confirmed serial regions, but unconfirmed ones could make up
      // the gap: report blanks so the engine says "unable to verify".
      final serialReads = [...serials];
      if (serialReads.length < CurrencyRules.frontSerialRegions &&
          serialReads.length + serialUncertain.length >=
              CurrencyRules.frontSerialRegions) {
        while (serialReads.length < CurrencyRules.frontSerialRegions) {
          serialReads.add(const SerialReadModel(text: '', confidence: 0));
        }
      }

      // Printed year: confirmed box -> detected (with OCR value if read);
      // only an unconfirmed box -> detected but low confidence; none -> missing.
      final yearUncertain = _uncertain(frontDets, YoloClass.printedYear).firstOrNull;
      final printedYear = yearBox != null
          ? PrintedYearModel(detected: true, value: yearValue, confidence: yearBox.score)
          : yearUncertain != null
              ? PrintedYearModel(detected: true, confidence: yearUncertain.score)
              : const PrintedYearModel(detected: false, confidence: 1);

      // ---- Step 2a: mark counting (lines / dots) ----
      // Count individual marks inside the best lines/dots box: YOLO boxes
      // the whole group (e.g. both Rs 1,000 dots in one box).
      sw = Stopwatch()..start();
      Future<int?> marksIn(YoloClass c) async {
        final best = _confirmed(frontDets, c).firstOrNull;
        if (best == null) return null;
        try {
          return await ImagePreprocessor.countMarks(f.pixels, best.box);
        } on Object catch (e) {
          debugPrint('Mark counting failed: $e');
          return null;
        }
      }

      final lineMarks = await marksIn(YoloClass.securityLines);
      final dotMarks = await marksIn(YoloClass.securityDots);
      timings['marks'] = lap(sw);
      debugPrint('Marks counted: lines=$lineMarks dots=$dotMarks');

      // ---- Build the per-side evidence ----
      final frontSide = SideDetectionModel(
        quality: f.quality,
        denomination: frontNote!.cls.denomination,
        denominationConfidence: frontNote.score,
        sbpSeals: _count(frontDets, YoloClass.sbpSeal, frontMax),
        securityThreads: _count(frontDets, YoloClass.securityThread, frontMax),
        securityLines: _count(frontDets, YoloClass.securityLines, frontMax,
            markCount: lineMarks),
        securityDots: _count(frontDets, YoloClass.securityDots, frontMax,
            markCount: dotMarks),
        printedYear: printedYear,
        serialNumbers: serialReads,
      );
      // Rules: back = denomination + 3 seals. The single thread is judged on
      // the front; lines/dots, serials and year are front-only.
      final backSide = SideDetectionModel(
        quality: b.quality,
        denomination: backNote!.cls.denomination,
        denominationConfidence: backNote.score,
        sbpSeals: _count(backDets, YoloClass.sbpSeal, backMax),
      );

      // ---- Step 2b: Rs 5,000 extras (microprint) ----
      // 2b. Rs 5,000 only: full-resolution inputs for the edge microprint
      //     and the genuine/counterfeit CNN. Other notes skip this work.
      final isRs5000 = frontNote.cls == YoloClass.rs5000 &&
          backNote.cls == YoloClass.rs5000;
      MicroprintModel? microprint;
      Rs5000Inputs? f5k, b5k;
      if (isRs5000) {
        sw = Stopwatch()..start();
        (f5k, b5k) = await (
          ImagePreprocessor.prepareRs5000(front.path, dir.path),
          ImagePreprocessor.prepareRs5000(back.path, dir.path),
        ).wait;
        timings['rs5000_prep'] = lap(sw);

        sw = Stopwatch()..start();
        microprint = await const MicroprintReader().read(
          5000,
          [...f5k.edgeStripPaths, ...b5k.edgeStripPaths],
          source: 'scan',
        );
        timings['microprint'] = lap(sw);
      }

      // ---- Step 3: classifiers (CNNs) ----
      // 3. Rs 5,000 CNNs: only when YOLO says both sides are Rs 5,000.
      // Variables below stay null when a model does not apply or did not run.
      AnomalyModel? anomaly;
      CounterfeitCnnModel? counterfeit;
      String? skipReason;
      String? rs5000Only;
      CounterfeitCnnModel? smallCnn;
      String? smallCnnSkipReason;
      if (isRs5000 && f5k != null && b5k != null) {
        sw = Stopwatch()..start();
        final cnn = await (_cnn ??= _load(Rs5000AnomalyClassifier.load, 'Rs 5,000 CNN'));
        final pf = cnn.predict(f.cnnInput);
        final pb = cnn.predict(b.cnnInput);
        timings['cnn'] = lap(sw);
        debugPrint('CNN synthetic-alteration: front=$pf back=$pb');
        anomaly = AnomalyModel(
          anomalyScore: math.max(pf, pb),
          model: Rs5000AnomalyClassifier.modelName,
          frontScore: pf,
          backScore: pb,
        );

        // Second, independent CNN: genuine vs counterfeit (from .pth).
        sw = Stopwatch()..start();
        final gc = await (_counterfeitCnn ??= _load(
            Pkr5000CounterfeitClassifier.load, 'Rs 5,000 genuine/counterfeit'));
        final cf = gc.counterfeitProbability(f5k.pkrInput);
        final cb = gc.counterfeitProbability(b5k.pkrInput);
        timings['cnn_counterfeit'] = lap(sw);
        debugPrint('CNN P(counterfeit): front=$cf back=$cb');
        counterfeit = CounterfeitCnnModel(
          frontCounterfeit: cf,
          backCounterfeit: cb,
          model: Pkr5000CounterfeitClassifier.modelName,
        );
      } else {
        rs5000Only = 'Only for Rs 5,000 notes · this is '
            '${frontNote.cls.denomination == null ? 'another note' : 'Rs ${frontNote.cls.denomination}'}';

        // Rs 10–1,000: separate MobileNetV3-Small genuine/fake classifier.
        // SWITCHED OFF: the whole block below is skipped while
        // kSmallCnnEnabled (currency_rules.dart) is false.
        // Only when both sides agree on a supported denomination; it never
        // runs for Rs 5,000. If it fails, report UNABLE TO VERIFY rather
        // than treating the note as genuine.
        final d = frontNote.cls.denomination;
        if (kSmallCnnEnabled &&
            d != null &&
            d == backNote.cls.denomination &&
            MobileNetV3SmallClassifier.supports(d)) {
          sw = Stopwatch()..start();
          try {
            final small = await (_smallCnn ??= MobileNetV3SmallClassifier.load());
            final pf = small.fakeProbability(f.cnnInput);
            final pb = small.fakeProbability(b.cnnInput);
            debugPrint('MobileNetV3-Small P(fake) Rs $d: front=$pf back=$pb');
            smallCnn = CounterfeitCnnModel(
              frontCounterfeit: pf,
              backCounterfeit: pb,
              model: MobileNetV3SmallClassifier.modelName,
            );
          } on Object catch (e) {
            debugPrint('MobileNetV3-Small failed: $e');
            _smallCnn = null; // allow a retry on the next scan
            smallCnnSkipReason =
                'The genuine/fake classifier could not run on this device';
          }
          timings['cnn_small'] = lap(sw);
        }
      }

      // ---- Step 3b: Quaid-e-Azam portrait on the front ----
      // Same idea as the monument check on the back: a small image classifier
      // looks at the whole front photo. A failure here is only logged; the
      // check then reports "not clear" instead of stopping the scan.
      sw = Stopwatch()..start();
      final portraitModel = await (_portrait ??= PortraitClassifier.tryLoad());
      var portraitResult = const PortraitResultModel.notInstalled();
      if (portraitModel != null) {
        try {
          final p = await portraitModel.classify(fs.prepared.pixels);
          debugPrint('Portrait ${front.path} → ${p.label} '
              '${p.confidence.toStringAsFixed(2)}');
          portraitResult = PortraitResultModel(
            modelAvailable: true,
            label: p.label,
            confidence: p.confidence,
            verified: portraitModel.verified,
            knownDenominations: portraitModel.knownDenominations,
          );
        } on Object catch (e) {
          debugPrint('Portrait classification failed: $e');
          portraitResult = PortraitResultModel(
            modelAvailable: true,
            verified: portraitModel.verified,
            knownDenominations: portraitModel.knownDenominations,
          );
        }
      }
      // Face-level model: is the portrait the genuine Quaid-e-Azam, or changed
      // (another person, glasses, earrings, nose pin, smile / sad mouth)?
      final faceModel = await (_portraitFace ??= PortraitClassifier.tryLoadFace());
      if (faceModel != null) {
        try {
          final f = await faceModel.classify(fs.prepared.pixels);
          debugPrint('Portrait face ${front.path} → ${f.label} '
              '${f.confidence.toStringAsFixed(2)}');
          portraitResult = PortraitResultModel(
            modelAvailable: portraitResult.modelAvailable,
            label: portraitResult.label,
            confidence: portraitResult.confidence,
            verified: portraitResult.verified,
            knownDenominations: portraitResult.knownDenominations,
            faceAvailable: true,
            faceLabel: f.label,
            faceConfidence: f.confidence,
            faceVerified: faceModel.verified,
          );
        } on Object catch (e) {
          debugPrint('Portrait face classification failed: $e');
          portraitResult = PortraitResultModel(
            modelAvailable: portraitResult.modelAvailable,
            label: portraitResult.label,
            confidence: portraitResult.confidence,
            verified: portraitResult.verified,
            knownDenominations: portraitResult.knownDenominations,
            faceAvailable: true,
            faceVerified: faceModel.verified,
          );
        }
      }
      timings['portrait'] = lap(sw);

      // ---- Step 4: assemble the evidence bundle ----
      // The monument result comes from the back-side scan done earlier.
      timings['total'] = lap(total);
      debugPrint('Timings (ms): $timings');

      return NoteAnalysisModel(
        isBanknote: true,
        banknoteConfidence: math.min(frontNote.score, backNote.score),
        front: frontSide,
        back: backSide,
        anomaly: anomaly,
        anomalySkipReason: skipReason,
        counterfeitCnn: counterfeit,
        smallCnn: smallCnn,
        smallCnnSkipReason: smallCnnSkipReason,
        microprint: microprint,
        monument: bs.monumentModelAvailable
            ? MonumentResultModel(
                modelAvailable: true,
                label: bs.monument?.label,
                confidence: bs.monument?.confidence ?? 0,
                verified: bs.monumentVerified,
                knownDenominations: bs.monumentKnown,
              )
            : const MonumentResultModel.notInstalled(),
        portrait: portraitResult,
        rs5000OnlyReason: rs5000Only,
        timingsMs: timings,
        detections: detections,
      );
    } finally {
      // Always remove the temporary crop folder, even after an error.
      dir.delete(recursive: true).ignore();
    }
  }

  // ---------------------------------------------------------------------------
  // Static helpers
  // ---------------------------------------------------------------------------

  /// Converts YOLO boxes from the letterboxed model input space back to
  /// working-image pixels.
  static List<YoloDetection> _toImage(List<YoloDetection> dets, Letterbox lb) => [
        for (final d in dets) YoloDetection(d.cls, d.score, lb.toImage(d.box)),
      ];

  /// Converts boxes to 0..1 fractions of the image size, so the UI can draw
  /// them on any screen size.
  static SideDetectionsModel _sideDetections(
    List<YoloDetection> dets,
    PreparedImage img,
  ) =>
      SideDetectionsModel(
        width: img.width,
        height: img.height,
        boxes: [
          for (final d in dets)
            DetectionBoxModel(
              classId: d.cls.id,
              label: d.cls.label,
              score: d.score,
              left: (d.box.left / img.width).clamp(0.0, 1.0),
              top: (d.box.top / img.height).clamp(0.0, 1.0),
              right: (d.box.right / img.width).clamp(0.0, 1.0),
              bottom: (d.box.bottom / img.height).clamp(0.0, 1.0),
            ),
        ],
      );

  /// The highest-scoring whole-note box (any denomination), or null if YOLO
  /// found no note.
  static YoloDetection? _bestNote(List<YoloDetection> dets) =>
      dets.where((d) => d.cls.isNote).fold<YoloDetection?>(
          null, (best, d) => best == null || d.score > best.score ? d : best);

  /// Boxes of class [c] with score at or above [confirmThreshold], best first.
  static List<YoloDetection> _confirmed(List<YoloDetection> dets, YoloClass c) =>
      dets.where((d) => d.cls == c && d.score >= confirmThreshold).toList()
        ..sort((a, b) => b.score.compareTo(a.score));

  /// Boxes of class [c] below [confirmThreshold] ("seen but unconfirmed"),
  /// best first.
  static List<YoloDetection> _uncertain(List<YoloDetection> dets, YoloClass c) =>
      dets.where((d) => d.cls == c && d.score < confirmThreshold).toList()
        ..sort((a, b) => b.score.compareTo(a.score));

  /// Confirmed boxes count. Boxes from 0.25 to 0.50 are uncertain. If the
  /// class produced no box at all but still scored at least
  /// [CurrencyRules.faintDetectionScore] somewhere, that counts as one
  /// uncertain sighting, so "barely visible" reads as unclear, not missing.
  static FeatureDetectionModel _count(
    List<YoloDetection> dets,
    YoloClass c,
    List<double> classMax, {
    int? markCount,
  }) {
    final ok = _confirmed(dets, c);
    final unsure = _uncertain(dets, c).length;
    final faint = ok.isEmpty &&
        unsure == 0 &&
        classMax[c.id] >= CurrencyRules.faintDetectionScore;
    return FeatureDetectionModel(
      count: ok.length,
      // With nothing confirmed the model is confident there are none.
      confidence: ok.isEmpty ? 1 : ok.map((d) => d.score).reduce(math.min),
      uncertainCount: unsure + (faint ? 1 : 0),
      markCount: markCount,
    );
  }

  /// Debug text listing the top score of every YOLO class.
  static String _fmtMax(List<double> m) => [
        for (final c in YoloClass.values)
          '${c.label}=${m[c.id].toStringAsFixed(3)}',
      ].join(' ');

  /// Runs ML Kit text recognition on one image file and returns its text
  /// lines with their confidence.
  static Future<List<OcrLine>> _ocr(TextRecognizer r, String path) async {
    final result = await r.processImage(InputImage.fromFilePath(path));
    return [
      for (final block in result.blocks)
        for (final line in block.lines) OcrLine(line.text, line.confidence),
    ];
  }

  /// Frees the native model resources. Call when the repository is no longer
  /// needed.
  Future<void> dispose() async {
    await (await _yolo)?.close();
    (await _cnn)?.close();
    (await _counterfeitCnn)?.close();
    (await _smallCnn)?.close();
    (await _monument)?.close();
    (await _portrait)?.close();
    (await _portraitFace)?.close();
  }
}
