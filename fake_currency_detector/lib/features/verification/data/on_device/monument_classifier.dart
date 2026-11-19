/// Recognises the monument printed on the back of a note.
///
/// In: the back-side pixels. Out: a [MonumentPrediction] (label, confidence,
/// all class probabilities). Each denomination has its own building, so the
/// result can confirm the denomination or catch a wrong note.
/// Model: `assets/models/monument_classifier.tflite` (MobileNet from
/// Teachable Machine / our training) with labels in `monument_labels.txt`.
/// The model is optional: if the files are missing, loading returns null.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'native_decoder.dart';

/// The monument printed on the back of each Pakistani note.
abstract final class Monuments {
  /// Denomination in rupees → name of the building on its back.
  static const Map<int, String> byDenomination = {
    10: 'Bab-e-Khyber',
    20: 'Mohenjo-daro',
    50: 'K2',
    100: 'Ziarat Residency',
    500: 'Badshahi Mosque',
    1000: 'Islamia College Peshawar',
    5000: 'Faisal Mosque',
  };

  /// Class names the model must use (Teachable Machine class names).
  static const List<String> classNames = [
    'monument_10',
    'monument_20',
    'monument_50',
    'monument_100',
    'monument_500',
    'monument_1000',
    'monument_5000',
    // "invalid" = not a monument from any note.
    'invalid',
  ];

  /// 'monument_100' → 100; 'invalid' or anything else → null.
  static int? denominationOf(String label) {
    final m = RegExp(r'^monument_(\d+)$').firstMatch(label.trim());
    final v = m == null ? null : int.parse(m.group(1)!);
    return byDenomination.containsKey(v) ? v : null;
  }

  /// Parses Teachable Machine's labels.txt ("0 monument_10" per line) or a
  /// plain list ("monument_10").
  static List<String> parseLabels(String text) => [
        for (final line in text.split(RegExp(r'\r?\n')))
          if (line.trim().isNotEmpty)
            line.trim().replaceFirst(RegExp(r'^\d+\s+'), ''),
      ];
}

/// One prediction from the monument model.
class MonumentPrediction {
  const MonumentPrediction({
    required this.label,
    required this.confidence,
    required this.probabilities,
  });

  /// Winning class name, e.g. 'monument_100' or 'invalid'.
  final String label;

  /// Probability of the winning class, 0 to 1.
  final double confidence;

  /// Probability of every class, keyed by class name.
  final Map<String, double> probabilities;

  /// Denomination of the winning class, or null for 'invalid'.
  int? get denomination => Monuments.denominationOf(label);
}

/// Optional Teachable Machine (MobileNet) image classifier for the back-side
/// monument. Bundled as `assets/models/monument_classifier.tflite` +
/// `assets/models/monument_labels.txt`. When the files are missing,
/// [tryLoad] returns null and the monument check reports "not installed".
class MonumentClassifier {
  MonumentClassifier._(this._interpreter, this.labels, this._size, this._input,
      this._output, this.verified, this.letterbox);

  /// Path of the TFLite model file inside the app assets.
  static const String modelAsset = 'assets/models/monument_classifier.tflite';

  /// Path of the text file listing class names, one per output.
  static const String labelsAsset = 'assets/models/monument_labels.txt';

  /// Written by tools/train_monument.py: {"verified": true/false, ...}.
  /// Missing → unverified.
  static const String infoAsset = 'assets/models/monument_model_info.json';

  /// The TFLite runtime object that actually runs the model.
  final Interpreter _interpreter;

  /// Class names in the same order as the model outputs.
  final List<String> labels;

  /// See [infoAsset]. Unverified models only produce warnings.
  final bool verified;

  /// `"preprocess": "letterbox"` in the info file (our training pipeline):
  /// keep the whole image, padded to a square. Otherwise Teachable Machine's
  /// centre-square crop.
  final bool letterbox;

  /// Denominations this model knows (from its labels).
  List<int> get knownDenominations =>
      [for (final l in labels) ?Monuments.denominationOf(l)];
  /// Side of the square model input in pixels (read from the model).
  final int _size;

  /// Input and output tensor descriptions (shape, type, quantisation).
  final Tensor _input;
  final Tensor _output;

  /// Loads the model, labels and optional info file. Returns null (never
  /// throws) if anything is missing or does not match.
  static Future<MonumentClassifier?> tryLoad() async {
    try {
      // Step 1: read the labels and load the model.
      final labels = Monuments.parseLabels(await rootBundle.loadString(labelsAsset));
      final interpreter = await Interpreter.fromAsset(
        modelAsset,
        options: InterpreterOptions()..threads = 4,
      );
      final input = interpreter.getInputTensor(0);
      final output = interpreter.getOutputTensor(0);
      final inShape = input.shape, outShape = output.shape;
      // Step 2: sanity checks: square RGB input, one output per label.
      if (inShape.length != 4 || inShape[1] != inShape[2] || inShape[3] != 3) {
        throw StateError('Unexpected monument model input $inShape');
      }
      if (outShape.last != labels.length) {
        throw StateError('Model has ${outShape.last} outputs but '
            '${labels.length} labels');
      }
      // Step 3: read the optional info file (verified flag, preprocessing).
      var verified = false, letterbox = false;
      try {
        final info = jsonDecode(await rootBundle.loadString(infoAsset));
        verified = info is Map && info['verified'] == true;
        letterbox = info is Map && info['preprocess'] == 'letterbox';
      } on Object {
        // No info file: unverified Teachable Machine model.
      }
      debugPrint('Monument model loaded: input $inShape ${input.type}, '
          'labels $labels, verified $verified, letterbox $letterbox');
      return MonumentClassifier._(
          interpreter, labels, inShape[1], input, output, verified, letterbox);
    } on Object catch (e) {
      debugPrint('Monument model not available: $e');
      return null;
    }
  }

  /// Quantised models take whole-number bytes instead of decimals.
  bool get _quantized => _input.type == TensorType.uint8;

  /// Classifies the monument in [pixels] (the back side, RGBA).
  /// Returns the best class with its confidence (0-1).
  Future<MonumentPrediction> classify(RgbaImage pixels) async {
    // Step 1: build the model input in a background isolate (worker thread).
    final size = _size, quantized = _quantized, pad = letterbox;
    final input = await Isolate.run(
        () => teachableMachineInput(pixels, size, quantized, letterbox: pad));

    // Step 2: run the model into a byte buffer (1 byte per class if
    // quantised, else 4 bytes per class).
    final n = labels.length;
    final outBytes = Uint8List(_output.type == TensorType.uint8 ? n : n * 4);
    _interpreter.run(input, outBytes);

    // Step 3: turn the bytes into probabilities. Quantised output is
    // (value - zeroPoint) * scale; float output is read directly.
    final probs = <double>[];
    if (_output.type == TensorType.uint8) {
      final q = _output.params;
      final scale = q.scale == 0 ? 1 / 255 : q.scale;
      for (final v in outBytes) {
        probs.add((v - q.zeroPoint) * scale);
      }
    } else {
      final f = outBytes.buffer.asFloat32List();
      probs.addAll(f.map((v) => v.toDouble()));
    }
    // Step 4: pick the class with the highest probability.
    var best = 0;
    for (var i = 1; i < n; i++) {
      if (probs[i] > probs[best]) best = i;
    }
    return MonumentPrediction(
      label: labels[best],
      confidence: probs[best].clamp(0.0, 1.0),
      probabilities: {for (var i = 0; i < n; i++) labels[i]: probs[i]},
    );
  }

  /// Teachable Machine preprocessing: centre square crop, resize to the
  /// model size, then float (x / 127.5 − 1) or raw uint8 for quantized
  /// exports. Returned as raw bytes for the interpreter.
  ///
  /// [size] is the square side in pixels; [letterbox] switches from centre
  /// crop to padding the whole image (see [letterbox] on the class).
  static Uint8List teachableMachineInput(
    RgbaImage pixels,
    int size,
    bool quantized, {
    bool letterbox = false,
  }) {
    // Step 1: make a square [size] x [size] image, either padded
    // (letterbox) or centre-cropped.
    final image = pixels.toImage();
    final img.Image resized;
    if (letterbox) {
      // Same as tools/train_monument.py letterbox_224: whole image, long
      // side to [size], centred on grey 114.
      final r = size / math.max(image.width, image.height);
      final w = math.max(1, (image.width * r).round());
      final h = math.max(1, (image.height * r).round());
      final scaled = img.copyResize(image,
          width: w, height: h, interpolation: img.Interpolation.average);
      resized = img.Image(width: size, height: size)
        ..clear(img.ColorRgb8(114, 114, 114));
      img.compositeImage(resized, scaled,
          dstX: (size - w) ~/ 2, dstY: (size - h) ~/ 2);
    } else {
      final side = math.min(image.width, image.height);
      final square = img.copyCrop(
        image,
        x: (image.width - side) ~/ 2,
        y: (image.height - side) ~/ 2,
        width: side,
        height: side,
      );
      resized = img.copyResize(square,
          width: size, height: size, interpolation: img.Interpolation.average);
    }
    // Step 2: write RGB values. Quantised: raw 0-255 bytes. Float: scaled
    // to -1..1 (x / 127.5 - 1), as Teachable Machine expects.
    if (quantized) {
      final out = Uint8List(size * size * 3);
      var i = 0;
      for (final p in resized) {
        out[i++] = p.r.toInt();
        out[i++] = p.g.toInt();
        out[i++] = p.b.toInt();
      }
      return out;
    }
    final out = Float32List(size * size * 3);
    var i = 0;
    for (final p in resized) {
      out[i++] = p.r / 127.5 - 1;
      out[i++] = p.g / 127.5 - 1;
      out[i++] = p.b / 127.5 - 1;
    }
    return out.buffer.asUint8List();
  }

  /// Frees the model's memory. Call when finished.
  void close() => _interpreter.close();
}
