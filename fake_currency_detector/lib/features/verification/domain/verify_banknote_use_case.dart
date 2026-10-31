import '../data/models/verification_result_model.dart';
import 'note_image_input.dart';
import 'currency_verification_repository.dart';
import 'verification_engine.dart';

/// Orchestrates: two-side gate → detection → rule engine.
class VerifyBanknoteUseCase {
  const VerifyBanknoteUseCase(this._repository, this._engine);

  final CurrencyVerificationRepository _repository;
  final VerificationEngine _engine;

  Future<VerificationResultModel> call({
    NoteImageInput? front,
    NoteImageInput? back,
  }) async {
    if (front == null || back == null) {
      return _engine.incomplete(hasFront: front != null);
    }
    final analysis = await _repository.analyzeBanknote(front: front, back: back);
    return _engine.evaluate(analysis, source: _repository.sourceLabel);
  }
}
