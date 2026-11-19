/// Cleans up OCR text into serial numbers and printed years.
///
/// In: lines of text that ML Kit OCR (reading text from pictures) read from
/// crops YOLO located. Out: a [SerialRead] (letters + 7 digits), a pair of
/// reconciled serial reads, or a 4-digit year. Pure text logic: no model
/// and no image work here.
library;

/// One OCR line with ML Kit's confidence (null on platforms that omit it).
class OcrLine {
  const OcrLine(this.text, [this.confidence]);

  /// The text OCR read on this line.
  final String text;

  /// OCR confidence 0-1, or null if the platform gives none.
  final double? confidence;
}

/// A serial read from one crop.
class SerialRead {
  const SerialRead(this.text, this.confidence, {this.raw = '', this.fixes = 0});

  /// A "nothing found" result.
  static const empty = SerialRead('', 0);

  /// Normalised serial (letters prefix + 7 digits), or '' if not found.
  final String text;

  /// Lowest line confidence, 0-1 (0.4 is used for an unreliable read).
  final double confidence;

  /// What OCR returned (alphanumerics only), for diagnostics.
  final String raw;

  /// Characters changed by look-alike correction (e.g. O→0 in digits).
  final int fixes;

  /// True when no serial was found.
  bool get isEmpty => text.isEmpty;
}

/// Cleans OCR text read from YOLO-located crops. YOLO11s decides *where*
/// the serial number and printed year are; this only reads *what* they say.
abstract final class NoteTextParser {
  /// Confidence assumed for an OCR line that has none.
  static const double defaultLineConfidence = 0.8;

  /// Pakistani serials: 2–3 letters followed by 7 digits, e.g. ATG8159424.
  static const int serialDigits = 7;

  /// Fewest letters allowed in the serial prefix.
  static const int minPrefix = 2;

  /// Most letters allowed in the serial prefix.
  static const int maxPrefix = 3;

  /// Letter → digit look-alikes, applied only inside the digit part.
  static const Map<String, String> _toDigit = {
    'O': '0', 'Q': '0', 'D': '0', 'U': '0',
    'I': '1', 'L': '1', 'J': '1',
    'Z': '2', 'S': '5', 'G': '6', 'T': '7', 'B': '8',
  };

  /// Digit → letter look-alikes, applied only inside the letter prefix.
  static const Map<String, String> _toLetter = {
    '0': 'O', '1': 'I', '2': 'Z', '4': 'A', '5': 'S',
    '6': 'G', '7': 'T', '8': 'B',
  };

  /// True for '0'-'9' (character codes 48-57).
  static bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  /// True for 'A'-'Z' (character codes 65-90).
  static bool _isLetter(String c) => c.codeUnitAt(0) >= 65 && c.codeUnitAt(0) <= 90;

  /// Maps common OCR letter/digit confusions inside numeric runs.
  static String fixDigits(String s) =>
      [for (final c in s.split('')) _toDigit[c] ?? c].join();

  /// Finds the serial anywhere in the crop's OCR text. All lines are joined
  /// (ML Kit often splits the letters from the digits, or the large and
  /// small digits of a progressive serial), then the best "letters + 7 digits"
  /// window is taken and look-alikes are corrected by position.
  static SerialRead serialFromCrop(List<OcrLine> lines) {
    if (lines.isEmpty) return SerialRead.empty;
    // Step 1: join all lines, upper-case, keep only letters and digits.
    final raw = lines
        .map((l) => l.text.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), ''))
        .join();
    // Step 2: overall confidence = the weakest line (cautious choice).
    final conf = lines
        .map((l) => l.confidence ?? defaultLineConfidence)
        .reduce((a, b) => a < b ? a : b);
    final chars = raw.split('');

    // Step 3: slide a 7-character window along the text. Each window that
    // could be 7 digits (allowing look-alike letters) is a candidate.
    SerialRead? best;
    var bestTrueDigits = -1;
    var bestFixes = 1 << 30;
    for (var start = 0; start + serialDigits <= chars.length; start++) {
      final run = chars.sublist(start, start + serialDigits);
      if (!run.every((c) => _isDigit(c) || _toDigit.containsKey(c))) continue;
      // Do not take 7 digits out of a longer number.
      if (start + serialDigits < chars.length &&
          _isDigit(chars[start + serialDigits])) {
        continue;
      }

      // Step 4: build the prefix: up to 3 letters right before the digits. A digit look-alike
      // is accepted when it is needed to reach 2 letters, or when a genuine
      // letter sits before it (e.g. the 7 in "A7G").
      final prefix = <String>[];
      var fixes = 0;
      var i = start - 1;
      while (i >= 0 && prefix.length < maxPrefix) {
        final c = chars[i];
        if (_isLetter(c)) {
          prefix.insert(0, c);
        } else if (_toLetter.containsKey(c) &&
            (prefix.length < minPrefix || (i > 0 && _isLetter(chars[i - 1])))) {
          prefix.insert(0, _toLetter[c]!);
          fixes++;
        } else {
          break;
        }
        i--;
      }
      if (prefix.length < minPrefix) continue;

      // Step 5: keep the best candidate: most real digits first, then the
      // fewest look-alike corrections.
      final trueDigits = run.where(_isDigit).length;
      fixes += serialDigits - trueDigits;
      final text = '${prefix.join()}${fixDigits(run.join())}';
      if (trueDigits > bestTrueDigits ||
          (trueDigits == bestTrueDigits && fixes < bestFixes)) {
        best = SerialRead(text, conf, raw: raw, fixes: fixes);
        bestTrueDigits = trueDigits;
        bestFixes = fixes;
      }
    }
    return best ?? SerialRead('', 0, raw: raw);
  }

  /// Combines two OCR passes (normal + enhanced crop) for each of the two
  /// serial regions into final reads.
  ///
  /// - Any reading of region A equal to any reading of region B → match.
  /// - Each region read the same way twice, but A ≠ B → a real mismatch.
  /// - Otherwise the OCR is not reliable enough → low confidence, which the
  ///   engine reports as UNABLE TO VERIFY, never as fake.
  static (SerialRead, SerialRead) reconcile(
    List<SerialRead> regionA,
    List<SerialRead> regionB,
  ) {
    // Step 1: ignore empty reads. If a region has none, return what we have.
    final a = regionA.where((r) => !r.isEmpty).toList();
    final b = regionB.where((r) => !r.isEmpty).toList();
    if (a.isEmpty || b.isEmpty) {
      return (
        a.firstOrNull ?? regionA.firstOrNull ?? SerialRead.empty,
        b.firstOrNull ?? regionB.firstOrNull ?? SerialRead.empty,
      );
    }
    // Step 2: any read of A equal to any read of B is a match.
    for (final x in a) {
      for (final y in b) {
        if (x.text == y.text) return (x, y);
      }
    }
    // Step 3: a region is "stable" when it read the same twice or more.
    // Both stable but different = real mismatch.
    bool stable(List<SerialRead> r) =>
        r.length >= 2 && r.every((e) => e.text == r.first.text);
    if (stable(a) && stable(b)) return (a.first, b.first);

    // Step 4: otherwise mark unstable reads with low confidence (0.4) so
    // the result is "unable to verify", not "fake".
    SerialRead unsure(List<SerialRead> r) =>
        SerialRead(r.first.text, 0.4, raw: r.first.raw, fixes: r.first.fixes);
    return (stable(a) ? a.first : unsure(a), stable(b) ? b.first : unsure(b));
  }

  /// Matches a standalone 4-digit year from 1940 to 2099.
  static final RegExp _year = RegExp(r'(?<![0-9])(19[4-9][0-9]|20[0-9]{2})(?![0-9])');

  /// Four-digit year from a printed-year crop, or null when not readable.
  /// Only years from 1947 (Pakistan's founding) to [maxYear] are accepted.
  static String? yearFromCrop(List<OcrLine> lines, {required int maxYear}) {
    for (final l in lines) {
      for (final m in _year.allMatches(fixDigits(l.text.toUpperCase()))) {
        final y = int.parse(m.group(1)!);
        if (y >= 1947 && y <= maxYear) return m.group(1);
      }
    }
    return null;
  }
}
