/// Riverpod state holder for the verification screens.
///
/// Starts the check, keeps its progress/result in [VerificationState], plays
/// the right vibration for each outcome, and defines the providers that wire
/// the repository, rule engine and use case together.
library;

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

/// Provides the rule engine that turns detections into a verdict.
final verificationEngineProvider =
    Provider<VerificationEngine>((ref) => const VerificationEngine());

/// Everything runs on the phone. `ApiCurrencyVerificationRepository` can be
/// swapped in here once a server exists.
final onDeviceRepositoryProvider =
    Provider<OnDeviceCurrencyVerificationRepository>((ref) {
  final repo = OnDeviceCurrencyVerificationRepository();
  // Free the repository's resources when the provider is disposed.
  ref.onDispose(repo.dispose);
  return repo;
});

/// The repository used by the use case (currently the on-device one).
final currencyVerificationRepositoryProvider =
    Provider<CurrencyVerificationRepository>(
  (ref) => ref.watch(onDeviceRepositoryProvider),
);

/// Front/back check run right after each capture (same YOLO scan is reused
/// by the analysis, so it costs no extra time later).
final sideClassifierProvider = Provider<SideClassifier>(
  (ref) => ref.watch(onDeviceRepositoryProvider),
);

/// Provides the use case, built from the repository and the rule engine.
final verifyBanknoteUseCaseProvider = Provider<VerifyBanknoteUseCase>(
  (ref) => VerifyBanknoteUseCase(
    ref.watch(currencyVerificationRepositoryProvider),
    ref.watch(verificationEngineProvider),
  ),
);

/// Where the check is now.
/// - idle: nothing started.
/// - analyzing: running (show a progress screen).
/// - completed: a result is ready.
/// - rejected: the image was not a banknote.
/// - failed: an error stopped the check.
enum VerificationStatus { idle, analyzing, completed, rejected, failed }

/// What the screens read: the status plus the result or the error.
class VerificationState {
  const VerificationState({
    this.status = VerificationStatus.idle,
    this.result,
    this.error,
  });

  /// Current step of the check.
  final VerificationStatus status;

  /// The result. Set when completed or rejected; null otherwise.
  final VerificationResultModel? result;

  /// The error. Set only when the status is failed.
  final VerificationException? error;
}

/// Runs verification and publishes [VerificationState] to the UI.
class VerificationController extends Notifier<VerificationState> {
  /// Counts runs. A finished run that is no longer the latest is ignored, so
  /// an old check cannot overwrite a newer one or a reset.
  int _run = 0;

  @override
  VerificationState build() => const VerificationState();

  /// Checks a note from its two photos and updates the state.
  /// A missing side gives an INCOMPLETE result (see the use case).
  Future<void> verify({NoteImageInput? front, NoteImageInput? back}) async {
    final run = ++_run;
    state = const VerificationState(status: VerificationStatus.analyzing);
    try {
      final result = await ref.read(verifyBanknoteUseCaseProvider)(
        front: front,
        back: back,
      );
      if (run != _run) return; // superseded or reset

      // Not a banknote: strong vibration and a "rejected" state.
      if (result.verdict == VerificationVerdict.notBanknote) {
        await Haptics.alert();
        state = VerificationState(
          status: VerificationStatus.rejected,
          result: result,
        );
        return;
      }

      // Different vibration for each kind of outcome.
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
      // Known failure (for example a missing model or a bad image).
      if (run != _run) return;
      await Haptics.warning();
      state = VerificationState(status: VerificationStatus.failed, error: e);
    } on Object catch (e) {
      // Any other error is wrapped as an "unknown" verification error.
      if (run != _run) return;
      state = VerificationState(
        status: VerificationStatus.failed,
        error: VerificationException(VerificationErrorKind.unknown, '$e'),
      );
    }
  }

  /// Re-reads the edge microprint from a close-up photo and re-runs the
  /// rules, keeping every other model output unchanged.
  /// Does nothing if there is no current result or no denomination.
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

    // Run the rules again with the new microprint reading.
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

  /// Clears the state back to idle and cancels any run still in progress.
  void reset() {
    _run++;
    state = const VerificationState();
  }
}

/// The provider screens watch to get the state and call [verify] / [reset].
final verificationControllerProvider =
    NotifierProvider<VerificationController, VerificationState>(
  VerificationController.new,
);
