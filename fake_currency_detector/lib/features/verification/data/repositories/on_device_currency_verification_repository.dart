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
import '../on_device/monument_classifier.dart';
import '../on_device/note_presence.dart';
import '../on_device/note_side_classifier.dart';
import '../on_device/page_detector.dart';
import '../on_device/partial_note_detector.dart';
import '../on_device/pkr5000_counterfeit_classifier.dart';
import '../on_device/note_text_parser.dart';
import '../on_device/rs5000_anomaly_classifier.dart';
import '../on_device/yolo_decoder.dart';
import '../on_device/yolo_detector.dart';

/// On-device pipeline. Each model keeps its own role:
/// - YOLO11s: is it a note, which denomination, and where/how many security
///   features (seals, thread, lines, dots, serial regions, printed year)
/// - ML Kit OCR: reads the text inside the YOLO serial-number / year boxes
/// - Rs 5,000 CNN: synthetic-alteration score, Rs 5,000 only, supporting
/// The rule engine (not this class) turns these outputs into a verdict.
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

  final PreparedImage prepared;

  /// Post-NMS boxes in working-image pixels.
  final List<YoloDetection> detections;
  final List<double> classMax;
  final int prepareMs;
  final int yoloMs;

  /// Back-side monument prediction (null when the model is not installed).
  final MonumentPrediction? monument;
  final bool monumentModelAvailable;
  final bool monumentVerified;
  final List<int> monumentKnown;
}

class OnDeviceCurrencyVerificationRepository
    implements CurrencyVerificationRepository, SideClassifier {
  OnDeviceCurrencyVerificationRepository({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  Future<YoloDetector>? _yolo;
  Future<Rs5000AnomalyClassifier>? _cnn;
  Future<Pkr5000CounterfeitClassifier>? _counterfeitCnn;
  Future<MonumentClassifier?>? _monument;

  /// Scans by image path. A path is a unique captured file, so a retake is a
  /// new entry; old entries are dropped on [forget].
  final Map<String, Future<SideScan>> _scans = {};

  /// Prepares [path] and runs YOLO11s once; later calls reuse the result.
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

  Future<SideScan> _scan(String path) async {
    final sw = Stopwatch()..start();
    final prepared = await ImagePreprocessor.prepare(path);
    final prepareMs = sw.elapsedMilliseconds;
    final yolo = await (_yolo ??= _load(YoloDetector.load, 'YOLO11s'));
    final (raw, classMax) = await yolo.detect(prepared.yoloInput);
    final yoloMs = sw.elapsedMilliseconds - prepareMs;

    // Optional monument model (Teachable Machine); ~tens of ms.
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
    );
    debugPrint('Side check $imagePath → $side, note ${check.noteDenomination}, '
        'monument ${check.monumentDenomination}');
    return check;
  }

  /// Below this a YOLO box is "seen but unconfirmed" and never counts.
  static const double confirmThreshold = CurrencyRules.minDetectionConfidence;

  @override
  String get sourceLabel => 'on-device';

  Future<T> _load<T>(Future<T> Function() loader, String what) =>
      loader().catchError((Object e) => throw VerificationException(
            VerificationErrorKind.unknown,
            'Could not load the $what model: $e',
          ));

  @override
  Future<NoteAnalysisModel> analyzeBanknote({
    required NoteImageInput front,
    required NoteImageInput back,
  }) async {
    final total = Stopwatch()..start();
    final timings = <String, int>{};
    int lap(Stopwatch s) => (s..stop()).elapsedMilliseconds;

    final dir = await Directory.systemTemp.createTemp('fcd_');
    try {
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

      // 1. Is there a banknote on each side at all?
      final frontNote = _bestNote(frontDets);
      final backNote = _bestNote(backDets);

      // 1a. A sheet of paper (A4 page, printout, photocopy) is rejected
      //     first, with instructions, whatever YOLO thinks it sees on it.
      final paper = [
        ?PageDetector.rejection(
          side: 'FRONT',
          aspectRatio: f.aspectRatio,
          paperWhiteFraction: f.paperWhiteFraction,
          noteCoverage: _coverage(frontNote, f),
        ),
        ?PageDetector.rejection(
          side: 'BACK',
          aspectRatio: b.aspectRatio,
          paperWhiteFraction: b.paperWhiteFraction,
          noteCoverage: _coverage(backNote, b),
        ),
      ];
      debugPrint('Paper check: front aspect ${f.aspectRatio.toStringAsFixed(2)} '
          'white ${f.paperWhiteFraction.toStringAsFixed(2)}; back aspect '
          '${b.aspectRatio.toStringAsFixed(2)} white '
          '${b.paperWhiteFraction.toStringAsFixed(2)}');
      // A note on printer paper is a photocopy / printout → FAKE.
      // A page with no real note content (no confident note class and no
      // security feature) is just "not a note" and falls through below.
      if (paper.isNotEmpty &&
          (_noteContent(frontDets) || _noteContent(backDets))) {
        timings['total'] = lap(total);
        return NoteAnalysisModel(
          isBanknote: false,
          banknoteConfidence: 0,
          rejectionKind: 'photocopy',
          rejectionReasons: paper,
          timingsMs: timings,
          detections: detections,
        );
      }

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

        SerialReadModel model(SerialRead r, List<SerialRead> pass) =>
            SerialReadModel(
              text: r.text,
              confidence: r.confidence,
              ocrReads: [for (final x in pass) x.raw],
            );

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

      final yearUncertain = _uncertain(frontDets, YoloClass.printedYear).firstOrNull;
      final printedYear = yearBox != null
          ? PrintedYearModel(detected: true, value: yearValue, confidence: yearBox.score)
          : yearUncertain != null
              ? PrintedYearModel(detected: true, confidence: yearUncertain.score)
              : const PrintedYearModel(detected: false, confidence: 1);

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

      // 3. Rs 5,000 CNNs: only when YOLO says both sides are Rs 5,000.
      AnomalyModel? anomaly;
      CounterfeitCnnModel? counterfeit;
      String? skipReason;
      String? rs5000Only;
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
      }

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
        rs5000OnlyReason: rs5000Only,
        timingsMs: timings,
        detections: detections,
      );
    } finally {
      dir.delete(recursive: true).ignore();
    }
  }

  static List<YoloDetection> _toImage(List<YoloDetection> dets, Letterbox lb) => [
        for (final d in dets) YoloDetection(d.cls, d.score, lb.toImage(d.box)),
      ];

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

  /// A confident note class (≥ 0.5) or any security-feature box. A page of
  /// plain text can get a weak note class (0.48 seen) but never features.
  static bool _noteContent(List<YoloDetection> dets) => dets.any((d) =>
      (d.cls.isNote && d.score >= confirmThreshold) ||
      NotePresence.featureClasses.contains(d.cls));

  /// Share of the image covered by YOLO's best note box.
  static double? _coverage(YoloDetection? note, PreparedImage img) =>
      note == null ? null : (note.box.area / (img.width * img.height)).clamp(0.0, 1.0);

  static YoloDetection? _bestNote(List<YoloDetection> dets) =>
      dets.where((d) => d.cls.isNote).fold<YoloDetection?>(
          null, (best, d) => best == null || d.score > best.score ? d : best);

  static List<YoloDetection> _confirmed(List<YoloDetection> dets, YoloClass c) =>
      dets.where((d) => d.cls == c && d.score >= confirmThreshold).toList()
        ..sort((a, b) => b.score.compareTo(a.score));

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

  static String _fmtMax(List<double> m) => [
        for (final c in YoloClass.values)
          '${c.label}=${m[c.id].toStringAsFixed(3)}',
      ].join(' ');

  static Future<List<OcrLine>> _ocr(TextRecognizer r, String path) async {
    final result = await r.processImage(InputImage.fromFilePath(path));
    return [
      for (final block in result.blocks)
        for (final line in block.lines) OcrLine(line.text, line.confidence),
    ];
  }

  Future<void> dispose() async {
    await (await _yolo)?.close();
    (await _cnn)?.close();
    (await _counterfeitCnn)?.close();
    (await _monument)?.close();
  }
}
