import '../data/models/note_analysis_model.dart';
import 'note_image_input.dart';

/// Source of detector output for a captured banknote.
///
/// Implementations throw `VerificationException` on failure.
abstract interface class CurrencyVerificationRepository {
  /// Label shown in diagnostics (e.g. "on-device", "api").
  String get sourceLabel;

  Future<NoteAnalysisModel> analyzeBanknote({
    required NoteImageInput front,
    required NoteImageInput back,
  });
}
