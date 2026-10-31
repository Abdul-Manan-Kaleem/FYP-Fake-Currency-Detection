/// One OCR line with ML Kit's confidence (null on platforms that omit it).
class OcrLine {
  const OcrLine(this.text, [this.confidence]);

  final String text;
  final double? confidence;
}

/// A serial read from one crop.
class SerialRead {
  const SerialRead(this.text, this.confidence, {this.raw = '', this.fixes = 0});

  static const empty = SerialRead('', 0);

  /// Normalised serial (letters prefix + 7 digits), or '' if not found.
  final String text;
  final double confidence;

  /// What OCR returned (alphanumerics only), for diagnostics.
  final String raw;

  /// Characters changed by look-alike correction (e.g. O→0 in digits).
  final int fixes;

  bool get isEmpty => text.isEmpty;
}

/// Cleans OCR text read from YOLO-located crops. YOLO11s decides *where*
/// the serial number and printed year are; this only reads *what* they say.
abstract final class NoteTextParser {
  static const double defaultLineConfidence = 0.8;

  /// Pakistani serials: 2–3 letters followed by 7 digits, e.g. ATG8159424.
  static const int serialDigits = 7;
  static const int minPrefix = 2;
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

  static bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
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
    final raw = lines
        .map((l) => l.text.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), ''))
        .join();
    final conf = lines
        .map((l) => l.confidence ?? defaultLineConfidence)
        .reduce((a, b) => a < b ? a : b);
    final chars = raw.split('');

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

      // Prefix: up to 3 letters right before the digits. A digit look-alike
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
    final a = regionA.where((r) => !r.isEmpty).toList();
    final b = regionB.where((r) => !r.isEmpty).toList();
    if (a.isEmpty || b.isEmpty) {
      return (
        a.firstOrNull ?? regionA.firstOrNull ?? SerialRead.empty,
        b.firstOrNull ?? regionB.firstOrNull ?? SerialRead.empty,
      );
    }
    for (final x in a) {
      for (final y in b) {
        if (x.text == y.text) return (x, y);
      }
    }
    bool stable(List<SerialRead> r) =>
        r.length >= 2 && r.every((e) => e.text == r.first.text);
    if (stable(a) && stable(b)) return (a.first, b.first);

    SerialRead unsure(List<SerialRead> r) =>
        SerialRead(r.first.text, 0.4, raw: r.first.raw, fixes: r.first.fixes);
    return (stable(a) ? a.first : unsure(a), stable(b) ? b.first : unsure(b));
  }

  static final RegExp _year = RegExp(r'(?<![0-9])(19[4-9][0-9]|20[0-9]{2})(?![0-9])');

  /// Four-digit year from a printed-year crop, or null when not readable.
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
