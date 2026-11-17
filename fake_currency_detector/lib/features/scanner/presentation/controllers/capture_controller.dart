/// Controller (the "brain") of the capture screen.
///
/// It runs the guided flow: scan front, flip, scan back, review. After each
/// photo it checks the side is right, then saves it in [CaptureState]. The
/// screen only listens to the state and calls the methods here.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/haptics.dart';
import '../../data/note_capture_service.dart';
import '../../../verification/domain/side_classifier.dart';
import '../../../verification/presentation/controllers/verification_controller.dart';
import '../../domain/capture_models.dart';

/// Riverpod provider that gives one shared [NoteCaptureService].
final noteCaptureServiceProvider =
    Provider<NoteCaptureService>((ref) => NoteCaptureService());

/// Drives the guided FRONT → flip → BACK → review flow.
class CaptureController extends Notifier<CaptureState> {
  /// Starting state: nothing captured, on the FRONT step.
  @override
  CaptureState build() => const CaptureState();

  // Shortcut to the capture service.
  NoteCaptureService get _service => ref.read(noteCaptureServiceProvider);

  /// Launches the native scanner (or gallery) for [side]. When a side is
  /// retaken from the review step the flow stays on review.
  Future<void> capture(
    NoteSide side, {
    bool fromGallery = false,
    bool basicCamera = false,
  }) async {
    // Step 1: Ignore taps while another capture is running, then mark busy.
    if (state.busy) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      // Step 2: Get a photo from the gallery, plain camera or scanner.
      final result = fromGallery
          ? await _service.pickFromGallery(side)
          : basicCamera
              ? await _service.basicCamera(side)
              : await _service.scan(side);
      // The user cancelled: just stop being busy.
      if (result == null) {
        state = state.copyWith(busy: false);
        return;
      }

      // Step 3: Front/back check right after capture. The same YOLO scan is reused
      // by the analysis, so this also makes "Analyze" faster later.
      state = state.copyWith(
        busyMessage: 'Checking side…',
      );
      final check = await _checkSide(result.path);

      // Step 4: Not a banknote at all: say so on the very first image and do not move
      // on to the next step.
      if (!check.looksLikeNote) {
        _forget([result.path]);
        await Haptics.alert();
        state = state.copyWith(
          busy: false,
          sideError: SideError.notABanknote,
          clearBusyMessage: true,
        );
        return;
      }

      // Step 5: Wrong side or wrong note? Delete the photo and show the
      // pop-up message; otherwise continue.
      final problem = _sideProblem(side, check);
      if (problem != null) {
        _forget([result.path]);
        await Haptics.alert();
        state = state.copyWith(
          busy: false,
          sideError: problem,
          clearBusyMessage: true,
        );
        return;
      }
      // Step 6: Photo accepted. Save it with the denomination found: from
      // the note itself for the front, from the monument for the back.
      await Haptics.capture();
      _store(
        side,
        result,
        side == NoteSide.front ? check.noteDenomination : check.monumentDenomination,
      );
    } on Object catch (e) {
      // Any failure: show the error. If the ML Kit scanner failed, remember
      // the side so the screen can offer the plain camera.
      state = state.copyWith(
        busy: false,
        clearBusyMessage: true,
        error: e is CaptureFailure ? e.message : 'Capture failed: $e',
        basicCameraSide:
            e is CaptureFailure && e.canUseBasicCamera ? side : null,
      );
    }
  }

  /// Asks the side classifier what the photo at [path] shows (front, back,
  /// or not a note). Returns [SideCheck.unknown] if the check itself fails.
  Future<SideCheck> _checkSide(String path) async {
    try {
      return await ref.read(sideClassifierProvider).checkSide(path);
    } on Object catch (e) {
      // Never block capture because of the check itself; analysis decides.
      debugPrint('Side check failed: $e');
      return SideCheck.unknown;
    }
  }

  /// Compares the [expected] side with what was detected in [check].
  /// Returns the matching [SideError], or null if all is fine or unclear.
  SideError? _sideProblem(NoteSide expected, SideCheck check) {
    final got = check.side;
    // Back shown while the front was asked for.
    if (expected == NoteSide.front && got == DetectedSide.back) {
      return SideError.backOnFront;
    }
    // Front shown while the back was asked for. If the front is already
    // saved, the user repeated the same side.
    if (expected == NoteSide.back && got == DetectedSide.front) {
      return state.front != null ? SideError.sameSideTwice : SideError.frontOnBack;
    }
    // Back of a different note: monument vs the front's denomination.
    final frontDenom = state.front?.denomination;
    final monument = check.monumentDenomination;
    if (expected == NoteSide.back &&
        frontDenom != null &&
        monument != null &&
        monument != frontDenom) {
      return SideError.wrongNote(found: monument, scanning: frontDenom);
    }
    return null; // matches, or not sure (the analysis will decide)
  }

  /// Tells the on-device repository to drop saved data for these image
  /// paths (so discarded photos are not kept).
  void _forget(Iterable<String> paths) =>
      ref.read(onDeviceRepositoryProvider).forget(paths);

  /// Saves an accepted photo for [side] and moves to the next step.
  /// An older photo of the same side is forgotten first.
  void _store(NoteSide side, CaptureResult result, [int? denomination]) {
    final replaced = side == NoteSide.front ? state.front : state.back;
    if (replaced != null) _forget([replaced.path]);
    final image = CapturedImage(
      path: result.path,
      side: side,
      source: result.source,
      capturedAt: DateTime.now(),
      denomination: denomination,
    );
    final wasReviewing = state.step == CaptureStep.review;

    // After the front: go to review if retaking or if the back already
    // exists; otherwise ask the user to flip the note.
    if (side == NoteSide.front) {
      state = state.copyWith(
        front: image,
        busy: false,
        clearBusyMessage: true,
        step: wasReviewing || state.back != null
            ? CaptureStep.review
            : CaptureStep.flip,
      );
    } else {
      // After the back: always go to review.
      state = state.copyWith(
        back: image,
        busy: false,
        clearBusyMessage: true,
        step: CaptureStep.review,
      );
    }
  }

  /// User says the note is flipped: move to the BACK step.
  void confirmFlip() => state = state.copyWith(step: CaptureStep.back);

  /// Jumps straight to the given [step].
  void goToStep(CaptureStep step) => state = state.copyWith(step: step);

  /// Clears the error and any side pop-up message.
  void clearError() => state = state.copyWith(clearError: true);

  /// Wipes everything and returns to the FRONT capture view.
  void reset() {
    _forget([?state.front?.path, ?state.back?.path]);
    state = const CaptureState();
  }
}

/// Riverpod provider that screens use to read the state and call the
/// controller.
final captureControllerProvider =
    NotifierProvider<CaptureController, CaptureState>(CaptureController.new);
