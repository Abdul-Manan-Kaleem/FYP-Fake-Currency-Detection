/// Gets a photo of one side of a banknote from the phone.
///
/// Three ways to get a photo: the ML Kit document scanner (best), the plain
/// camera, or the gallery. Camera and gallery photos are cropped by hand.
/// The controller (capture_controller.dart) calls this file.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/capture_models.dart';

/// A finished photo: where the file is saved and how it was taken.
class CaptureResult {
  const CaptureResult(this.path, this.source);

  /// File path of the saved JPEG image.
  final String path;

  /// Which method produced the photo (scanner, camera or gallery).
  final CaptureSource source;
}

/// Error thrown when capturing a photo fails; [message] is shown to the user.
class CaptureFailure implements Exception {
  const CaptureFailure(this.message, {this.canUseBasicCamera = false});

  /// Readable explanation of what went wrong.
  final String message;

  /// The ML Kit scanner could not start; the plain camera is an option.
  final bool canUseBasicCamera;

  @override
  String toString() => message;
}

/// Wraps ML Kit's native document scanner (auto-contour detection,
/// perspective warp and background removal) with a camera/gallery fallback.
class NoteCaptureService {
  NoteCaptureService({ImagePicker? picker, ImageCropper? cropper})
      : _picker = picker ?? ImagePicker(),
        _cropper = cropper ?? ImageCropper();

  // Plugin that opens the camera or gallery.
  final ImagePicker _picker;
  // Plugin that shows the manual crop screen.
  final ImageCropper _cropper;

  /// ML Kit's document scanner is Android-only (Google Play services).
  bool get supportsDocumentScanner =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Scans one side of the note with the ML Kit document scanner.
  /// Uses the plain camera instead on phones that do not support it.
  /// Returns `null` when the user cancels.
  /// Throws [CaptureFailure] if the scanner cannot start.
  Future<CaptureResult?> scan(NoteSide side) async {
    // Step 1: Phones without the scanner use the camera + manual crop.
    if (!supportsDocumentScanner) {
      return _cameraFallback(side);
    }

    // Step 2: Set up the scanner: JPEG output, one page only, base mode
    // (crop and rotate only: no filters, no auto enhance, so the image stays
    // exactly as the camera saw it) and no gallery import.
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.jpeg},
        mode: ScannerMode.base,
        pageLimit: 1,
        isGalleryImport: false,
      ),
    );
    try {
      // Step 3: Open the scanner screen and wait for the user.
      final result = await scanner.scanDocument();
      final images = result.images ?? const <String>[];
      // No image means the user left without scanning.
      if (images.isEmpty) return null;
      return CaptureResult(_toFilePath(images.first), CaptureSource.documentScanner);
    } on PlatformException catch (e) {
      // Step 4: A cancel is not an error. Anything else becomes a
      // [CaptureFailure] with a helpful message.
      final msg = '${e.code} ${e.message}'.toLowerCase();
      if (msg.contains('cancel')) return null;
      // Never fall back silently: the plain camera has no edge detection,
      // auto-capture or auto-crop, so the user must know which one they get.
      debugPrint('Document scanner failed: ${e.code} ${e.message} ${e.details}');
      throw CaptureFailure(
        'ML Kit document scanner could not start (${e.message ?? e.code}). '
        'It needs Google Play services and downloads its scanner module on '
        'first use, so check the internet connection and that Google Play '
        'services is up to date.',
        canUseBasicCamera: true,
      );
    } finally {
      // Always release the scanner, whether it worked or failed.
      await scanner.close();
    }
  }

  /// Lets the user choose a photo from the gallery, then crop it by hand.
  /// Returns `null` if the user cancels either step.
  Future<CaptureResult?> pickFromGallery(NoteSide side) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (picked == null) return null;
    final cropped = await _crop(picked.path, side);
    return cropped == null ? null : CaptureResult(cropped, CaptureSource.gallery);
  }

  /// Plain camera + manual free crop. No edge detection or auto-capture.
  Future<CaptureResult?> basicCamera(NoteSide side) => _cameraFallback(side);

  /// Takes a photo with the rear camera, then lets the user crop it.
  Future<CaptureResult?> _cameraFallback(NoteSide side) async {
    final shot = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (shot == null) return null;
    final cropped = await _crop(shot.path, side);
    return cropped == null ? null : CaptureResult(cropped, CaptureSource.camera);
  }

  /// Manual crop with a free crop frame: drag the corners onto the note's
  /// edges, pinch to zoom in or out. No forced aspect ratio, because a locked
  /// frame makes the photo always fill it, which blocked zooming out (about
  /// 87%) on whole-photo uploads. The real shape of the crop is also what the
  /// half-note check needs to see.
  /// Takes the image at [path] and returns the path of the cropped copy,
  /// or `null` if the user cancels.
  Future<String?> _crop(String path, NoteSide side) async {
    final title = 'Crop ${side.label}: drag corners to the note edges';
    final file = await _cropper.cropImage(
      sourcePath: path,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 92,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: title,
          toolbarColor: AppColors.onyx,
          statusBarLight: false,
          toolbarWidgetColor: AppColors.textPrimary,
          backgroundColor: AppColors.onyxDeep,
          activeControlsWidgetColor: AppColors.cyan,
          cropFrameColor: AppColors.cyan,
          cropGridColor: AppColors.cyan.withValues(alpha: 0.3),
          // false = free-style frame (corners can be dragged freely).
          lockAspectRatio: false,
          hideBottomControls: false,
          initAspectRatio: CropAspectRatioPreset.original,
          aspectRatioPresets: const [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.ratio16x9,
            CropAspectRatioPreset.ratio3x2,
          ],
        ),
        IOSUiSettings(
          title: title,
          aspectRatioLockEnabled: false,
          resetAspectRatioEnabled: true,
          aspectRatioPickerButtonHidden: false,
        ),
      ],
    );
    return file?.path;
  }

  /// Converts a `file:` address into a normal file path; plain paths are
  /// returned unchanged.
  static String _toFilePath(String uriOrPath) {
    if (uriOrPath.startsWith('file:')) return Uri.parse(uriOrPath).toFilePath();
    return uriOrPath;
  }

  /// True if a file exists at [path].
  static bool exists(String path) => File(path).existsSync();
}
