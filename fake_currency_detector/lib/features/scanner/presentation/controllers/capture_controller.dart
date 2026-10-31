import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/haptics.dart';
import '../../data/note_capture_service.dart';
import '../../../verification/domain/side_classifier.dart';
import '../../../verification/presentation/controllers/verification_controller.dart';
import '../../domain/capture_models.dart';

final noteCaptureServiceProvider =
    Provider<NoteCaptureService>((ref) => NoteCaptureService());

/// Drives the guided FRONT → flip → BACK → review flow.
class CaptureController extends Notifier<CaptureState> {
  @override
  CaptureState build() => const CaptureState();

  NoteCaptureService get _service => ref.read(noteCaptureServiceProvider);

  /// Launches the native scanner (or gallery) for [side]. When a side is
  /// retaken from the review step the flow stays on review.
  Future<void> capture(
    NoteSide side, {
    bool fromGallery = false,
    bool basicCamera = false,
  }) async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final result = fromGallery
          ? await _service.pickFromGallery(side)
          : basicCamera
              ? await _service.basicCamera(side)
              : await _service.scan(side);
      if (result == null) {
        state = state.copyWith(busy: false);
        return;
      }

      // Front/back check right after capture. The same YOLO scan is reused
      // by the analysis, so this also makes "Analyze" faster later.
      state = state.copyWith(
        busyMessage: 'Note ki side check ho rahi hai… · Checking side',
      );
      final check = await _checkSide(result.path);
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
      await Haptics.capture();
      _store(
        side,
        result,
        side == NoteSide.front ? check.noteDenomination : check.monumentDenomination,
      );
    } on Object catch (e) {
      state = state.copyWith(
        busy: false,
        clearBusyMessage: true,
        error: e is CaptureFailure ? e.message : 'Capture failed: $e',
        basicCameraSide:
            e is CaptureFailure && e.canUseBasicCamera ? side : null,
      );
    }
  }

  Future<SideCheck> _checkSide(String path) async {
    try {
      return await ref.read(sideClassifierProvider).checkSide(path);
    } on Object catch (e) {
      // Never block capture because of the check itself; analysis decides.
      debugPrint('Side check failed: $e');
      return SideCheck.unknown;
    }
  }

  SideError? _sideProblem(NoteSide expected, SideCheck check) {
    final got = check.side;
    if (expected == NoteSide.front && got == DetectedSide.back) {
      return SideError.backOnFront;
    }
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

  void _forget(Iterable<String> paths) =>
      ref.read(onDeviceRepositoryProvider).forget(paths);

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
      state = state.copyWith(
        back: image,
        busy: false,
        clearBusyMessage: true,
        step: CaptureStep.review,
      );
    }
  }

  void confirmFlip() => state = state.copyWith(step: CaptureStep.back);

  void goToStep(CaptureStep step) => state = state.copyWith(step: step);

  void clearError() => state = state.copyWith(clearError: true);

  /// Wipes everything and returns to the FRONT capture view.
  void reset() {
    _forget([?state.front?.path, ?state.back?.path]);
    state = const CaptureState();
  }
}

final captureControllerProvider =
    NotifierProvider<CaptureController, CaptureState>(CaptureController.new);
