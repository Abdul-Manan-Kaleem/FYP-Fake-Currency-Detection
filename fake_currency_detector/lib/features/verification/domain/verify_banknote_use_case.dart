/// The single entry point that checks a banknote from two photos.
///
/// The controller calls this. It asks the repository for raw detections, then
/// asks the rule engine to turn them into a verdict.
library;

import '../data/models/verification_result_model.dart';
import 'note_image_input.dart';
import 'currency_verification_repository.dart';
import 'verification_engine.dart';

/// Orchestrates: two-side gate → detection → rule engine.
class VerifyBanknoteUseCase {
  const VerifyBanknoteUseCase(this._repository, this._engine);

  /// Runs the detectors (YOLO, OCR, classifiers).
  final CurrencyVerificationRepository _repository;

  /// Applies the rules and builds the final result.
  final VerificationEngine _engine;

  /// Verifies a note. Both sides are needed: if either is missing the result
  /// is INCOMPLETE and no detection runs.
  Future<VerificationResultModel> call({
    NoteImageInput? front,
    NoteImageInput? back,
  }) async {
    // Two-side gate: stop early if a photo is missing.
    if (front == null || back == null) {
      return _engine.incomplete(hasFront: front != null);
    }
    // Detect first, then let the rule engine decide.
    final analysis = await _repository.analyzeBanknote(front: front, back: back);
    return _engine.evaluate(analysis, source: _repository.sourceLabel);
  }
}
