import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/verification_exception.dart';
import '../../../../core/utils/haptics.dart';
import '../../data/models/verification_result_model.dart';
import '../../data/on_device/microprint_reader.dart';
import '../../data/repositories/on_device_currency_verification_repository.dart';
import '../../domain/note_image_input.dart';
import '../../domain/side_classifier.dart';
import '../../domain/currency_verification_repository.dart';
import '../../domain/verification_engine.dart';
import '../../domain/verify_banknote_use_case.dart';

final verificationEngineProvider =
    Provider<VerificationEngine>((ref) => const VerificationEngine());

/// Everything runs on the phone. `ApiCurrencyVerificationRepository` can be
/// swapped in here once a server exists.
final onDeviceRepositoryProvider =
    Provider<OnDeviceCurrencyVerificationRepository>((ref) {
  final repo = OnDeviceCurrencyVerificationRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

final currencyVerificationRepositoryProvider =
    Provider<CurrencyVerificationRepository>(
  (ref) => ref.watch(onDeviceRepositoryProvider),
);

/// Front/back check run right after each capture (same YOLO scan is reused
/// by the analysis, so it costs no extra time later).
final sideClassifierProvider = Provider<SideClassifier>(
  (ref) => ref.watch(onDeviceRepositoryProvider),
);

final verifyBanknoteUseCaseProvider = Provider<VerifyBanknoteUseCase>(
  (ref) => VerifyBanknoteUseCase(
    ref.watch(currencyVerificationRepositoryProvider),
    ref.watch(verificationEngineProvider),
  ),
);

enum VerificationStatus { idle, analyzing, completed, rejected, failed }

class VerificationState {
  const VerificationState({
    this.status = VerificationStatus.idle,
    this.result,
    this.error,
  });

  final VerificationStatus status;
  final VerificationResultModel? result;
  final VerificationException? error;
}

class VerificationController extends Notifier<VerificationState> {
  int _run = 0;

  @override
  VerificationState build() => const VerificationState();

  Future<void> verify({NoteImageInput? front, NoteImageInput? back}) async {
    final run = ++_run;
    state = const VerificationState(status: VerificationStatus.analyzing);
    try {
      final result = await ref.read(verifyBanknoteUseCaseProvider)(
        front: front,
        back: back,
      );
      if (run != _run) return; // superseded or reset

      if (result.verdict == VerificationVerdict.notBanknote) {
        await Haptics.alert();
        state = VerificationState(
          status: VerificationStatus.rejected,
          result: result,
        );
        return;
      }

      switch (result.verdict) {
        case VerificationVerdict.real:
          await Haptics.success();
        case VerificationVerdict.suspicious || VerificationVerdict.fake:
          await Haptics.warning();
        default:
          await Haptics.tap();
      }
      state = VerificationState(
        status: VerificationStatus.completed,
        result: result,
      );
    } on VerificationException catch (e) {
      if (run != _run) return;
      await Haptics.warning();
      state = VerificationState(status: VerificationStatus.failed, error: e);
    } on Object catch (e) {
      if (run != _run) return;
      state = VerificationState(
        status: VerificationStatus.failed,
        error: VerificationException(VerificationErrorKind.unknown, '$e'),
      );
    }
  }

  /// Re-reads the edge microprint from a close-up photo and re-runs the
  /// rules, keeping every other model output unchanged.
  Future<void> applyMicroprintCloseUp(List<String> paths) async {
    final current = state.result;
    final analysis = current?.analysis;
    final denom = analysis?.front?.denomination;
    if (current == null || analysis == null || denom == null) return;

    final closeUp = await const MicroprintReader().read(
      denom,
      paths,
      source: 'close-up',
    );
    // Keep whichever reading is more informative.
    final scan = analysis.microprint;
    final better = scan == null ||
            closeUp.conflicting != null ||
            closeUp.occurrences >= scan.occurrences
        ? closeUp
        : scan;

    final updated = ref.read(verificationEngineProvider).evaluate(
          analysis.withMicroprint(better),
          source: current.source,
        );
    await Haptics.tap();
    state = VerificationState(
      status: VerificationStatus.completed,
      result: updated,
    );
  }

  void reset() {
    _run++;
    state = const VerificationState();
  }
}

final verificationControllerProvider =
    NotifierProvider<VerificationController, VerificationState>(
  VerificationController.new,
);
