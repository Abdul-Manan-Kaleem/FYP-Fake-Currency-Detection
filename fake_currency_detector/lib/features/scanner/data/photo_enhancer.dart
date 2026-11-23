/// Manual photo enhancement.
///
/// The app never enhances a photo by itself: the original photo is the
/// default and is what gets checked. Only when the user turns the Enhance
/// switch ON (capture review step) is an enhanced COPY made here. The original
/// file is never changed, so turning Enhance OFF gives the original back.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as img;

/// Makes enhanced copies of photos (auto levels: the darkest pixel becomes
/// black and the brightest white, colours kept).
abstract final class PhotoEnhancer {
  /// Writes an enhanced copy of the photo at [path] next to it and returns the
  /// new path. Returns [path] itself if the photo cannot be decoded, so the
  /// original is used rather than failing.
  static Future<String> enhance(String path) =>
      Isolate.run(() => enhanceSync(path));

  /// Does the work of [enhance] on the calling isolate.
  static String enhanceSync(String path) {
    final image = img.decodeImage(File(path).readAsBytesSync());
    if (image == null) return path;
    // Auto levels on every channel; no resizing and no sharpening.
    final out = img.normalize(image, min: 0, max: 255);
    final dot = path.lastIndexOf('.');
    final target =
        '${dot > 0 ? path.substring(0, dot) : path}_enhanced.jpg';
    File(target).writeAsBytesSync(img.encodeJpg(out, quality: 95));
    return target;
  }
}
