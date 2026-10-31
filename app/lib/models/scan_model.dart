class ScanModel {
  final String id;
  final String noteValue;
  final bool isAuthentic;
  final double confidence;
  final DateTime date;

  ScanModel({
    required this.id,
    required this.noteValue,
    required this.isAuthentic,
    required this.confidence,
    required this.date,
  });
}
