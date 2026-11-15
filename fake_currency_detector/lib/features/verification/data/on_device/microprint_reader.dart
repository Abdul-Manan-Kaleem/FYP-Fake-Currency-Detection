/// Checks the tiny repeated denomination text along a Rs 5,000 note border.
///
/// In: the denomination YOLO found plus OCR text read from edge-strip or
/// close-up images. Out: a [MicroprintModel] with how many times the
/// expected number appeared (and any conflicting number).
/// Uses Google ML Kit text recognition (OCR = reading text from pictures);
/// no model of our own.
library;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../domain/currency_rules.dart';
import '../models/note_analysis_model.dart';
import 'note_text_parser.dart';

/// Reads the tiny repeated denomination text printed along the border of
/// the Rs 5,000 note ("5000 5000 5000…"). No model training:
/// the expected text is the denomination YOLO11s detected, so OCR only has to
/// find it repeated.
abstract final class MicroprintRules {
  /// Repeats of the expected value needed to pass (set in CurrencyRules).
  static const int minOccurrences = CurrencyRules.microprintMinOccurrences;

  /// Values whose repetition on the border would contradict the detected
  /// denomination (e.g. "1000 1000 1000" on a note YOLO calls Rs 5,000).
  static const Set<int> conflictCandidates = {500, 1000, 5000};

  /// Counts the expected value and any clearly conflicting denomination in
  /// OCR text. Text is digit-normalised and spaces removed, because repeated
  /// microprint is often read as one long run ("500050005000").
  ///
  /// [expected] is the denomination, [texts] the OCR results, [source] a
  /// label for where the text came from (used in logs/results).
  static MicroprintModel evaluate(
    int expected,
    List<String> texts, {
    required String source,
  }) {
    // Step 1: keep only digits (fixing look-alike letters) and join all
    // texts with '|' so counts cannot span two separate images.
    final digits = [
      for (final t in texts)
        NoteTextParser.fixDigits(t.toUpperCase()).replaceAll(RegExp('[^0-9]'), ''),
    ].join('|');

    // Step 2: count the expected value.
    final found = _count(digits, '$expected');
    // Step 3: look for a conflicting denomination. A conflicting value must not be a substring of the expected one
    // (every "5000" contains "500"), and only counts when the expected value
    // is absent.
    int? conflict;
    var conflictCount = 0;
    if (found == 0) {
      for (final other in conflictCandidates) {
        if (other == expected || '$expected'.contains('$other')) continue;
        final n = _count(digits, '$other');
        if (n >= minOccurrences && n > conflictCount) {
          conflict = other;
          conflictCount = n;
        }
      }
    }

    // Step 4: build the result; the sample (first 48 chars) is for display.
    final sample = digits.replaceAll('|', ' ').trim();
    return MicroprintModel(
      expected: expected,
      occurrences: found,
      source: source,
      conflicting: conflict,
      conflictingOccurrences: conflictCount,
      sample: sample.length > 48 ? '${sample.substring(0, 48)}…' : sample,
    );
  }

  /// Non-overlapping occurrences of [needle] in [haystack].
  static int _count(String haystack, String needle) {
    var n = 0, i = 0;
    while ((i = haystack.indexOf(needle, i)) != -1) {
      n++;
      i += needle.length;
    }
    return n;
  }
}

/// ML Kit OCR over edge strips or a close-up photo.
class MicroprintReader {
  const MicroprintReader();

  /// Runs OCR on each image in [imagePaths] and scores the result with
  /// [MicroprintRules.evaluate]. [expected] is the denomination; [source]
  /// names the image type. Stops early once enough repeats are found.
  Future<MicroprintModel> read(
    int expected,
    List<String> imagePaths, {
    required String source,
  }) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final texts = <String>[];
    try {
      for (final p in imagePaths) {
        try {
          final r = await recognizer.processImage(InputImage.fromFilePath(p));
          texts.add(r.text);
        } on Object catch (e) {
          debugPrint('Microprint OCR failed on $p: $e');
        }
        // Enough repeats found: the remaining strips cannot change a PASS.
        if (MicroprintRules.evaluate(expected, texts, source: source).occurrences >=
            MicroprintRules.minOccurrences) {
          break;
        }
      }
    } finally {
      await recognizer.close();
    }
    final m = MicroprintRules.evaluate(expected, texts, source: source);
    debugPrint('Microprint ($source): expected $expected ×${m.occurrences}, '
        'conflict ${m.conflicting} ×${m.conflictingOccurrences}, read "${m.sample}"');
    return m;
  }
}
