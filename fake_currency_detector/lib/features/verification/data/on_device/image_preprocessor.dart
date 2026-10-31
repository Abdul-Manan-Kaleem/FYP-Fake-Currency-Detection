import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/note_analysis_model.dart';
import 'native_decoder.dart';
import 'yolo_decoder.dart';

/// Ultralytics-style letterbox geometry, used to map boxes back.
class Letterbox {
  const Letterbox({required this.scale, required this.padX, required this.padY});

  final double scale;
  final double padX;
  final double padY;

  /// Letterboxed-input box → working-image box.
  BoxRect toImage(BoxRect b) =>
      b.map((x) => (x - padX) / scale, (y) => (y - padY) / scale);
}

/// Everything derived from one decode of a captured side.
class PreparedImage {
  const PreparedImage({
    required this.pixels,
    required this.width,
    required this.height,
    required this.yoloInput,
    required this.letterbox,
    required this.cnnInput,
    required this.quality,
    required this.aspectRatio,
    required this.paperWhiteFraction,
  });

  /// Working copy (long side ≤ [ImagePreprocessor.workingLongSide]) kept in
  /// memory. All boxes refer to it; OCR crops and mark counting use it
  /// directly, with no JPEG written or decoded again.
  final RgbaImage pixels;
  final int width;
  final int height;

  /// float32 [1, 3, 640, 640] planar RGB in 0–1 (the TFLite input is BCHW).
  final Float32List yoloInput;
  final Letterbox letterbox;

  /// float32 [1, 224, 224, 3] RGB in 0–255 for the Rs 5,000
  /// synthetic-alteration CNN (plain resize, as before).
  final Float32List cnnInput;

  final ImageQualityModel quality;

  /// Long edge / short edge of the capture. A-series paper is 1.41.
  final double aspectRatio;

  /// Share of pixels that look like blank paper (bright and colourless).
  final double paperWhiteFraction;
}

/// Extra inputs needed only once YOLO has confirmed a Rs 5,000 note, built
/// from the full-resolution capture.
class Rs5000Inputs {
  const Rs5000Inputs({required this.pkrInput, required this.edgeStripPaths});

  /// float32 [1, 224, 224, 3] RGB in 0–255 for the genuine/counterfeit CNN,
  /// resized with PIL's antialiased bilinear filter exactly like torchvision
  /// `Resize((224, 224))` in training. ImageNet normalisation is inside the
  /// model.
  final Float32List pkrInput;

  /// Border strips (top, bottom, left, right), turned so text runs
  /// horizontally and enlarged for OCR of the edge microprint.
  final List<String> edgeStripPaths;
}

abstract final class ImagePreprocessor {
  static const int yoloSize = 640;
  static const int cnnSize = 224;
  static const int workingLongSide = 2048;

  /// Ultralytics letterbox pad colour.
  static const int padValue = 114;

  static const double sharpVariance = 120;
  static const double fullGlareFraction = 0.25;

  /// Decodes [path] once with the native codec, already scaled to the
  /// working size, then builds every model input in a background isolate.
  static Future<PreparedImage> prepare(String path) async {
    final pixels = await NativeDecoder.decode(path, maxLongSide: workingLongSide);
    return Isolate.run(() => fromPixels(pixels));
  }

  /// Test/desktop path: decode with the `image` package instead.
  static PreparedImage prepareSync(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Unsupported or corrupt image file.');
    }
    var image = img.bakeOrientation(decoded);
    if (math.max(image.width, image.height) > workingLongSide) {
      image = image.width >= image.height
          ? img.copyResize(image, width: workingLongSide,
              interpolation: img.Interpolation.average)
          : img.copyResize(image, height: workingLongSide,
              interpolation: img.Interpolation.average);
    }
    return fromPixels(RgbaImage.fromImage(image));
  }

  static PreparedImage fromPixels(RgbaImage pixels) {
    final image = pixels.toImage();
    final (yolo, letterbox) = _letterbox(image);
    return PreparedImage(
      pixels: pixels,
      width: image.width,
      height: image.height,
      yoloInput: yolo,
      letterbox: letterbox,
      cnnInput: _cnnTensor(image),
      quality: _quality(image),
      aspectRatio: math.max(image.width, image.height) /
          math.max(1, math.min(image.width, image.height)),
      paperWhiteFraction: paperWhiteFraction(image),
    );
  }

  /// Resize keeping aspect ratio, centre on a 114-grey square, scale to 0–1,
  /// and lay out channels-first.
  static (Float32List, Letterbox) _letterbox(img.Image image) {
    final scale = math.min(yoloSize / image.width, yoloSize / image.height);
    final nw = (image.width * scale).round();
    final nh = (image.height * scale).round();
    final resized = img.copyResize(image,
        width: nw, height: nh, interpolation: img.Interpolation.linear);
    final padX = ((yoloSize - nw) / 2).floorToDouble();
    final padY = ((yoloSize - nh) / 2).floorToDouble();

    const plane = yoloSize * yoloSize;
    final out = Float32List(3 * plane)..fillRange(0, 3 * plane, padValue / 255);
    final ox = padX.toInt(), oy = padY.toInt();
    for (var y = 0; y < nh; y++) {
      final row = (y + oy) * yoloSize + ox;
      for (var x = 0; x < nw; x++) {
        final p = resized.getPixel(x, y);
        final i = row + x;
        out[i] = p.r / 255;
        out[plane + i] = p.g / 255;
        out[2 * plane + i] = p.b / 255;
      }
    }
    return (out, Letterbox(scale: scale, padX: padX, padY: padY));
  }

  /// Rs 5,000-only inputs, decoded again from the original full-resolution
  /// capture (microprint is tiny, so nothing may be downscaled first).
  static Future<Rs5000Inputs> prepareRs5000(String path, String outDir) async {
    // Native full-resolution decode; resize and strip cutting off the UI
    // isolate.
    final full = await NativeDecoder.decode(path);
    final tag = '${path.hashCode.toUnsigned(32)}';
    return Isolate.run(() => Rs5000Inputs(
          pkrInput: pilBilinearRgba(
              full.rgba, full.width, full.height, cnnSize, cnnSize),
          edgeStripPaths: writeEdgeStrips(full.toImage(), outDir, tag),
        ));
  }

  /// Minimum Laplacian variance (grayscale, 1,000 px wide band) for a
  /// microprint close-up to count as in focus.
  static const double closeUpSharpVariance = 60;

  /// Close-up photo of the microprint: measures sharpness inside the guide
  /// band (middle of the frame) and writes that band for OCR.
  static Future<({double sharpness, String bandPath})> analyzeCloseUp(
    String path,
    String outDir,
  ) async {
    final px = await NativeDecoder.decode(path, maxLongSide: 2400);
    final band = '$outDir/closeup_${DateTime.now().microsecondsSinceEpoch}.bmp';
    final sharpness = await Isolate.run(() {
      final image = px.toImage();
      // Guide box: central 84% width × 34% height of the photo.
      final crop = img.copyCrop(
        image,
        x: (image.width * 0.08).round(),
        y: (image.height * 0.33).round(),
        width: (image.width * 0.84).round(),
        height: (image.height * 0.34).round(),
      );
      File(band).writeAsBytesSync(img.encodeBmp(crop));
      return laplacianVariance(img.copyResize(crop, width: 1000));
    });
    return (sharpness: sharpness, bandPath: band);
  }

  /// Variance of the 4-neighbour Laplacian on grayscale: low = blurry.
  static double laplacianVariance(img.Image image) {
    final g = img.grayscale(img.Image.from(image));
    final w = g.width, h = g.height;
    final lum = Float64List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        lum[y * w + x] = g.getPixel(x, y).r.toDouble();
      }
    }
    var sum = 0.0, sq = 0.0;
    var n = 0;
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final c = y * w + x;
        final l = lum[c - 1] + lum[c + 1] + lum[c - w] + lum[c + w] - 4 * lum[c];
        sum += l;
        sq += l * l;
        n++;
      }
    }
    if (n == 0) return 0;
    final mean = sum / n;
    return sq / n - mean * mean;
  }

  /// Share of the short side covered by each border strip.
  static const double edgeBand = 0.10;

  /// Border strips are enlarged until their short side is at least this.
  static const int minStripHeight = 180;

  /// Cuts the four border bands of the full-resolution note, rotates the
  /// side bands so their text runs horizontally, enlarges them, and writes
  /// JPEGs for OCR.
  static List<String> writeEdgeStrips(img.Image image, String outDir, String tag) {
    final band = (math.min(image.width, image.height) * edgeBand).round();
    if (band < 8) return const [];
    final w = image.width, h = image.height;
    final strips = <img.Image>[
      img.copyCrop(image, x: 0, y: 0, width: w, height: band),
      img.copyCrop(image, x: 0, y: h - band, width: w, height: band),
      img.copyRotate(img.copyCrop(image, x: 0, y: 0, width: band, height: h), angle: 90),
      img.copyRotate(img.copyCrop(image, x: w - band, y: 0, width: band, height: h), angle: -90),
    ];
    final paths = <String>[];
    for (final (i, strip) in strips.indexed) {
      var s = strip;
      if (s.height < minStripHeight) {
        s = img.copyResize(s,
            height: minStripHeight, interpolation: img.Interpolation.cubic);
      }
      // BMP: nothing to compress, so writing is nearly instant.
      final p = '$outDir/edge_${tag}_$i.bmp';
      File(p).writeAsBytesSync(img.encodeBmp(s));
      paths.add(p);
    }
    return paths;
  }

  /// Blank-paper pixels: bright (all channels ≥ 200) and colourless
  /// (channel spread ≤ 28). Banknotes are printed edge to edge and rarely
  /// exceed a few percent; a sheet of paper is mostly this.
  static double paperWhiteFraction(img.Image image) {
    final small = img.copyResize(image, width: 256);
    var white = 0;
    for (final p in small) {
      final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
      final lo = math.min(r, math.min(g, b));
      final hi = math.max(r, math.max(g, b));
      if (lo >= 200 && hi - lo <= 28) white++;
    }
    return white / (small.width * small.height);
  }

  // --- PIL-compatible resize ----------------------------------------------

  /// Port of Pillow's `Image.resize(size, Image.BILINEAR)` (antialiased
  /// triangle filter, 22-bit fixed point, horizontal then vertical pass,
  /// uint8 between passes). Returns HWC RGB floats in 0–255.
  static Float32List pilBilinearRgb(img.Image src, int outW, int outH) {
    final px = RgbaImage.fromImage(src);
    return pilBilinearRgba(px.rgba, px.width, px.height, outW, outH);
  }

  /// Same as [pilBilinearRgb], straight from packed RGBA bytes (no per-pixel
  /// objects, which matters on a 12-megapixel capture).
  static Float32List pilBilinearRgba(
    Uint8List rgba,
    int w,
    int h,
    int outW,
    int outH,
  ) {
    final horiz =
        _resamplePass(rgba, w, h, outW, horizontal: true, srcChannels: 4);
    final both = _resamplePass(horiz, outW, h, outH, horizontal: false);
    final out = Float32List(both.length);
    for (var k = 0; k < both.length; k++) {
      out[k] = both[k].toDouble();
    }
    return out;
  }

  static const int _precisionBits = 32 - 8 - 2;

  static (List<int>, List<int>, List<List<int>>) _coeffs(int inSize, int outSize) {
    final scale = inSize / outSize;
    final filterScale = scale < 1.0 ? 1.0 : scale;
    final support = 1.0 * filterScale; // bilinear filter support = 1
    final ss = 1.0 / filterScale;
    final bounds0 = <int>[], bounds1 = <int>[], kernels = <List<int>>[];
    for (var xx = 0; xx < outSize; xx++) {
      final center = (xx + 0.5) * scale;
      var xmin = (center - support + 0.5).floor();
      if (xmin < 0) xmin = 0;
      var xmax = (center + support + 0.5).floor();
      if (xmax > inSize) xmax = inSize;
      xmax -= xmin;
      final k = List<double>.filled(xmax, 0);
      var ww = 0.0;
      for (var x = 0; x < xmax; x++) {
        final t = ((x + xmin - center + 0.5) * ss).abs();
        final v = t < 1.0 ? 1.0 - t : 0.0;
        k[x] = v;
        ww += v;
      }
      final fixed = <int>[
        for (final v in k)
          () {
            final n = ww == 0 ? v : v / ww;
            final f = n * (1 << _precisionBits);
            return f < 0 ? (f - 0.5).truncate() : (f + 0.5).truncate();
          }(),
      ];
      bounds0.add(xmin);
      bounds1.add(xmax);
      kernels.add(fixed);
    }
    return (bounds0, bounds1, kernels);
  }

  static int _clip8(int v) {
    if (v >= (1 << (_precisionBits + 8))) return 255;
    if (v <= 0) return 0;
    return v >> _precisionBits;
  }

  static Uint8List _resamplePass(
    Uint8List src,
    int w,
    int h,
    int outSize, {
    required bool horizontal,
    int srcChannels = 3,
  }) {
    final inSize = horizontal ? w : h;
    final (xmins, counts, kernels) = _coeffs(inSize, outSize);
    final ow = horizontal ? outSize : w;
    final oh = horizontal ? h : outSize;
    final out = Uint8List(ow * oh * 3);
    const half = 1 << (_precisionBits - 1);
    for (var y = 0; y < oh; y++) {
      for (var x = 0; x < ow; x++) {
        final o = horizontal ? x : y;
        final xmin = xmins[o], n = counts[o], k = kernels[o];
        var r = half, g = half, b = half;
        for (var t = 0; t < n; t++) {
          final si = horizontal
              ? (y * w + xmin + t) * srcChannels
              : ((xmin + t) * w + x) * srcChannels;
          r += src[si] * k[t];
          g += src[si + 1] * k[t];
          b += src[si + 2] * k[t];
        }
        final oi = (y * ow + x) * 3;
        out[oi] = _clip8(r);
        out[oi + 1] = _clip8(g);
        out[oi + 2] = _clip8(b);
      }
    }
    return out;
  }

  static Float32List _cnnTensor(img.Image image) {
    final resized = img.copyResize(image,
        width: cnnSize, height: cnnSize, interpolation: img.Interpolation.linear);
    final out = Float32List(cnnSize * cnnSize * 3);
    var i = 0;
    for (var y = 0; y < cnnSize; y++) {
      for (var x = 0; x < cnnSize; x++) {
        final p = resized.getPixel(x, y);
        out[i++] = p.r.toDouble();
        out[i++] = p.g.toDouble();
        out[i++] = p.b.toDouble();
      }
    }
    return out;
  }

  static ImageQualityModel _quality(img.Image image) {
    final small = img.grayscale(img.copyResize(image, width: 480));
    final w = small.width, h = small.height;
    final lum = Float64List(w * h);
    var sum = 0.0;
    var blown = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final v = small.getPixel(x, y).r.toDouble();
        lum[y * w + x] = v;
        sum += v;
        if (v >= 250) blown++;
      }
    }
    var lapSum = 0.0, lapSq = 0.0;
    var n = 0;
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final c = y * w + x;
        final l = lum[c - 1] + lum[c + 1] + lum[c - w] + lum[c + w] - 4 * lum[c];
        lapSum += l;
        lapSq += l * l;
        n++;
      }
    }
    final mean = n == 0 ? 0.0 : lapSum / n;
    final variance = n == 0 ? 0.0 : lapSq / n - mean * mean;
    final total = w * h;
    return ImageQualityModel(
      blurScore: (1 - variance / sharpVariance).clamp(0.0, 1.0),
      glareScore: (blown / total / fullGlareFraction).clamp(0.0, 1.0),
      brightness: sum / total / 255,
    );
  }

  /// Counts separate dark marks (security dots or dash lines) inside one
  /// YOLO box. YOLO boxes the whole group, so this recovers the number of
  /// marks. Returns null when nothing sensible is found. Supporting
  /// evidence only: it never fails a check on its own.
  static Future<int?> countMarks(RgbaImage pixels, BoxRect box) =>
      Isolate.run(() => countMarksIn(pixels.toImage(), box));

  static int? countMarksIn(img.Image image, BoxRect box) {
    final mx = box.width * 0.04, my = box.height * 0.04;
    final x = (box.left - mx).clamp(0, image.width - 1).toInt();
    final y = (box.top - my).clamp(0, image.height - 1).toInt();
    final r = (box.right + mx).clamp(x + 1, image.width).toInt();
    final b = (box.bottom + my).clamp(y + 1, image.height).toInt();
    var crop = img.grayscale(
        img.copyCrop(image, x: x, y: y, width: r - x, height: b - y));
    if (math.min(crop.width, crop.height) < 48) {
      final s = 48 / math.min(crop.width, crop.height);
      crop = img.copyResize(crop,
          width: (crop.width * s).round(), height: (crop.height * s).round());
    }
    final w = crop.width, h = crop.height, total = w * h;
    final lum = Uint8List(total);
    final hist = List<int>.filled(256, 0);
    for (var j = 0; j < h; j++) {
      for (var i = 0; i < w; i++) {
        final v = crop.getPixel(i, j).r.toInt();
        lum[j * w + i] = v;
        hist[v]++;
      }
    }

    // Otsu threshold: marks are the darker class.
    var sumAll = 0.0;
    for (var t = 0; t < 256; t++) {
      sumAll += t * hist[t];
    }
    var sumB = 0.0, wB = 0, best = 0.0, threshold = 0;
    for (var t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += t * hist[t];
      final mB = sumB / wB, mF = (sumAll - sumB) / wF;
      final between = wB * wF * (mB - mF) * (mB - mF);
      if (between > best) {
        best = between;
        threshold = t;
      }
    }

    // 8-connected components of dark pixels.
    final seen = Uint8List(total);
    final stack = <int>[];
    var marks = 0;
    for (var start = 0; start < total; start++) {
      if (seen[start] == 1 || lum[start] > threshold) continue;
      var area = 0;
      seen[start] = 1;
      stack.add(start);
      while (stack.isNotEmpty) {
        final p = stack.removeLast();
        area++;
        final px = p % w, py = p ~/ w;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final nx = px + dx, ny = py + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            final q = ny * w + nx;
            if (seen[q] == 0 && lum[q] <= threshold) {
              seen[q] = 1;
              stack.add(q);
            }
          }
        }
      }
      // Ignore specks and anything that is basically the background.
      if (area >= total * 0.015 && area <= total * 0.5) marks++;
    }
    return marks == 0 ? null : marks;
  }

  /// Cuts each box (working-image coords) out for OCR and writes two
  /// versions: the plain crop and an enhanced one (grayscale, contrast
  /// stretched, enlarged). Reading both lets OCR misreads be spotted instead
  /// of being taken as a real serial mismatch. Tall crops are rotated
  /// upright. Returns (plain, enhanced) paths per box.
  static Future<List<(String, String)>> crops(
    RgbaImage pixels,
    List<BoxRect> boxes,
    String outDir,
  ) =>
      Isolate.run(() {
        final image = pixels.toImage();
        final out = <(String, String)>[];
        final stamp = DateTime.now().microsecondsSinceEpoch;
        for (final (i, b) in boxes.indexed) {
          // Generous margins: a clipped first/last character is a false
          // mismatch.
          final mx = b.width * 0.15, my = b.height * 0.30;
          final x = (b.left - mx).clamp(0, image.width - 1).toInt();
          final y = (b.top - my).clamp(0, image.height - 1).toInt();
          final r = (b.right + mx).clamp(x + 1, image.width).toInt();
          final btm = (b.bottom + my).clamp(y + 1, image.height).toInt();
          var crop = img.copyCrop(image, x: x, y: y, width: r - x, height: btm - y);
          if (crop.height > crop.width * 1.3) crop = img.copyRotate(crop, angle: -90);
          if (crop.height < 64) {
            crop = img.copyResize(crop,
                height: 64, interpolation: img.Interpolation.cubic);
          }

          var enhanced = img.normalize(img.grayscale(img.Image.from(crop)),
              min: 0, max: 255);
          if (enhanced.height < 128) {
            enhanced = img.copyResize(enhanced,
                height: 128, interpolation: img.Interpolation.cubic);
          }

          final plain = '$outDir/crop_${stamp}_${i}_a.bmp';
          final enh = '$outDir/crop_${stamp}_${i}_b.bmp';
          File(plain).writeAsBytesSync(img.encodeBmp(crop));
          File(enh).writeAsBytesSync(img.encodeBmp(enhanced));
          out.add((plain, enh));
        }
        return out;
      });
}
