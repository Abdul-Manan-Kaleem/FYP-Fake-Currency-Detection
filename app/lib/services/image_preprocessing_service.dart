import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

class ImagePreprocessingService {
  /// Core Utility Function: Image Pre-processing for AI Model Extraction
  /// 
  /// 1. Takes a captured XFile from the camera.
  /// 2. Crops exactly to the 290x155 alignment frame mapped on the screen.
  /// 3. Optimizes lighting and normalizes colors for computer vision.
  /// 4. Resizes the final mapped image to 224x224 (Standard CNN / AI Input size).
  /// 5. Returns the finalized byte array (Uint8List).
  Future<Uint8List?> processImageForAI(XFile capturedFile) async {
    try {
      // 1. Read raw byte stream from the camera cache
      final bytes = await File(capturedFile.path).readAsBytes();
      
      // Decode image structure 
      img.Image? originalImage = img.decodeImage(bytes);
      if (originalImage == null) return null;

      // Fix any rotational metadata (Hardware cameras often rotate images 90 degrees natively)
      originalImage = img.bakeOrientation(originalImage);

      // 2. Crop exactly to the 290x155 alignment frame
      // Since hardware camera resolutions are massive (e.g., 4000x3000), we calculate 
      // the strict mathematical ratio of the UI frame (290/155) mapped to the native resolution.
      const double frameAspectRatio = 290.0 / 155.0;
      
      int cropWidth = originalImage.width;
      int cropHeight = (cropWidth / frameAspectRatio).round();
      
      // Safety bounds if the camera ratio is reversed
      if (cropHeight > originalImage.height) {
        cropHeight = originalImage.height;
        cropWidth = (cropHeight * frameAspectRatio).round();
      }

      int offsetX = (originalImage.width - cropWidth) ~/ 2;
      int offsetY = (originalImage.height - cropHeight) ~/ 2;

      // Execute deep center-crop
      img.Image croppedImage = img.copyCrop(
        originalImage,
        x: offsetX,
        y: offsetY,
        width: cropWidth,
        height: cropHeight,
      );

      // 3. Optimize lighting and normalize colors
      // Standardizes the image pixels, bumping contrast and exposure slightly to
      // expose micro-patterns and UV textures more cleanly to the AI tensor blocks.
      img.Image optimizedImage = img.adjustColor(
        croppedImage, 
        brightness: 1.1,  // +10% exposure boost to equalize dark environments
        contrast: 1.25,   // +25% contrast punch for edge-detection mapping
        saturation: 1.1,  // +10% vibrancy to lift faint color shifts
      );

      // 4. Resize it to 224x224 (Standard ImageNet / TFLite input dimension limit)
      img.Image resizedImage = img.copyResize(
        optimizedImage,
        width: 224,
        height: 224,
        interpolation: img.Interpolation.linear,
      );

      // 5. Return the image as a byte array for future AI model consumption
      return Uint8List.fromList(img.encodeJpg(resizedImage, quality: 95));

    } catch (e) {
      // In a production environment, tie this to crashlytics.
      print("PreProcessing Error: Failed to crunch image tensor - $e");
      return null;
    }
  }
}
