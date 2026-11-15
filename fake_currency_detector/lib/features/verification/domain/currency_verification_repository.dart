/// The contract for anything that can analyse a banknote photo pair.
///
/// The use case calls this; the on-device repository (YOLO, OCR, MobileNetV3
/// on the phone) is the real implementation.
library;

import '../data/models/note_analysis_model.dart';
import 'note_image_input.dart';

/// Source of detector output for a captured banknote.
///
/// Implementations throw `VerificationException` on failure.
abstract interface class CurrencyVerificationRepository {
  /// Label shown in diagnostics (e.g. "on-device", "api").
  String get sourceLabel;

  /// Runs the detectors on both sides and returns the raw findings.
  /// This does NOT decide the verdict; the rule engine does that later.
  Future<NoteAnalysisModel> analyzeBanknote({
    required NoteImageInput front,
    required NoteImageInput back,
  });
}
