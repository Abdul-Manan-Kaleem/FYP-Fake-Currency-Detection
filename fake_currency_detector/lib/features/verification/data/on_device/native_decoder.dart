import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// Decoded pixels: tightly packed RGBA, row-major. Plain data, so it can be
/// sent to background isolates.
class RgbaImage {
  const RgbaImage(this.width, this.height, this.rgba);

  final int width;
  final int height;
  final Uint8List rgba;

  /// Wraps the same bytes as an `image` package image (no pixel copy).
  img.Image toImage() => img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgba.buffer,
        bytesOffset: rgba.offsetInBytes,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );

  static RgbaImage fromImage(img.Image image) {
    final rgba = image.convert(numChannels: 4, format: img.Format.uint8)
        .getBytes(order: img.ChannelOrder.rgba);
    return RgbaImage(image.width, image.height, rgba);
  }
}

/// JPEG/PNG decoding with the platform's native codec (Android's hardware
/// accelerated decoder via the Flutter engine). Several times faster than
/// decoding in Dart, and can downscale while decoding.
abstract final class NativeDecoder {
  /// Decodes [path]; if [maxLongSide] is set and the image is larger, it is
  /// scaled down during decoding, keeping its aspect ratio.
  static Future<RgbaImage> decode(String path, {int? maxLongSide}) async {
    final bytes = await File(path).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    int? targetWidth, targetHeight;
    final w = descriptor.width, h = descriptor.height;
    if (maxLongSide != null && (w > maxLongSide || h > maxLongSide)) {
      // Constrain one side only, so the codec keeps the aspect ratio.
      if (w >= h) {
        targetWidth = maxLongSide;
      } else {
        targetHeight = maxLongSide;
      }
    }
    final codec = await descriptor.instantiateCodec(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final result = RgbaImage(image.width, image.height, data!.buffer.asUint8List());
      image.dispose();
      return result;
    } finally {
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }
}
