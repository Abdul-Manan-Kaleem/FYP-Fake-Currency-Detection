/// Turns saved scans into CSV text (opens in Excel / Google Sheets).
///
/// Pure function, no I/O, so it is easy to test.
library;

import '../data/scan_record.dart';

/// Escapes one CSV cell: wraps it in quotes when it holds a comma, a quote or
/// a line break, and doubles any quote inside.
String csvCell(Object? value) {
  final s = value?.toString() ?? '';
  if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// Column titles, in the same order as [csvRow].
List<String> csvHeader() => [
      'id',
      'timestamp',
      'denomination_rs',
      'final_result',
      'confidence_percent',
      'raw_score_percent',
      'penalty',
      for (final f in kRecordedFeatures) columnOf(f),
      'reasons',
    ];

/// One CSV row for [r].
List<Object?> csvRow(ScanRecord r) => [
      r.id,
      r.scannedAt.toIso8601String(),
      r.denomination,
      r.verdict,
      r.confidencePct,
      r.rawScore,
      r.penalty,
      for (final f in kRecordedFeatures) r.features[f.name] ?? 'notRun',
      r.summary,
    ];

/// The whole CSV file text: a header line, then one line per scan.
/// Lines end with CRLF as the CSV standard (RFC 4180) says.
String scansToCsv(Iterable<ScanRecord> records) {
  final lines = <String>[
    csvHeader().map(csvCell).join(','),
    for (final r in records) csvRow(r).map(csvCell).join(','),
  ];
  return '${lines.join('\r\n')}\r\n';
}
