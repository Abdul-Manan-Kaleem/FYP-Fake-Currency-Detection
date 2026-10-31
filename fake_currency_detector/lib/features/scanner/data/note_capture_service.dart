import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/capture_models.dart';

class CaptureResult {
  const CaptureResult(this.path, this.source);

  final String path;
  final CaptureSource source;
}

class CaptureFailure implements Exception {
  const CaptureFailure(this.message, {this.canUseBasicCamera = false});

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

  final ImagePicker _picker;
  final ImageCropper _cropper;

  /// ML Kit's document scanner is Android-only (Google Play services).
  bool get supportsDocumentScanner =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Returns `null` when the user cancels.
  Future<CaptureResult?> scan(NoteSide side) async {
    if (!supportsDocumentScanner) {
      return _cameraFallback(side);
    }

    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.jpeg},
        mode: ScannerMode.full,
        pageLimit: 1,
        isGalleryImport: false,
      ),
    );
    try {
      final result = await scanner.scanDocument();
      final images = result.images ?? const <String>[];
      if (images.isEmpty) return null;
      return CaptureResult(_toFilePath(images.first), CaptureSource.documentScanner);
    } on PlatformException catch (e) {
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
      await scanner.close();
    }
  }

  /// Gallery upload with a manual crop locked to the banknote aspect ratio.
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

  static String _toFilePath(String uriOrPath) {
    if (uriOrPath.startsWith('file:')) return Uri.parse(uriOrPath).toFilePath();
    return uriOrPath;
  }

  static bool exists(String path) => File(path).existsSync();
}
