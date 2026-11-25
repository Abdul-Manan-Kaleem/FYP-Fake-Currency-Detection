/// Recognises the Quaid-e-Azam portrait side (the FRONT) of a note.
///
/// Same design as the monument classifier (monument_classifier.dart), applied
/// to the front side: In: the front-side pixels. Out: a [PortraitPrediction]
/// (label, confidence, all class probabilities). Each denomination prints the
/// portrait in its own design and colours, so the result can confirm the
/// denomination or catch a front that does not belong to the note.
/// Model: `assets/models/portrait_classifier.tflite` (MobileNetV2, trained by
/// `tools/train_monument.py --kind portrait`) with labels in
/// `portrait_labels.txt`. The model is optional: if the files are missing,
/// loading returns null and the check reports "not installed".
library;

import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'monument_classifier.dart';
import 'native_decoder.dart';

/// Labels of the portrait model.
abstract final class Portraits {
  /// Class names the model must use.
  static const List<String> classNames = [
    'portrait_10',
    'portrait_20',
    'portrait_50',
    'portrait_100',
    'portrait_500',
    'portrait_1000',
    'portrait_5000',
    // "invalid" = not the front of a note (for example the back).
    'invalid',
  ];

  /// 'portrait_100' -> 100; 'invalid' or anything else -> null.
  static int? denominationOf(String label) {
    final m = RegExp(r'^portrait_(\d+)$').firstMatch(label.trim());
    final v = m == null ? null : int.parse(m.group(1)!);
    return const {10, 20, 50, 100, 500, 1000, 5000}.contains(v) ? v : null;
  }
}

/// One prediction from the portrait model.
class PortraitPrediction {
  const PortraitPrediction({
    required this.label,
    required this.confidence,
    required this.probabilities,
  });

  /// Winning class name, e.g. 'portrait_100' or 'invalid'.
  final String label;

  /// Probability of the winning class, 0 to 1.
  final double confidence;

  /// Probability of every class, keyed by class name.
  final Map<String, double> probabilities;

  /// Denomination of the winning class, or null for 'invalid'.
  int? get denomination => Portraits.denominationOf(label);
}

/// Optional image classifier for the front-side Quaid-e-Azam portrait.
/// Bundled as `assets/models/portrait_classifier.tflite` +
/// `assets/models/portrait_labels.txt`. When the files are missing,
/// [tryLoad] returns null and the portrait check reports "not installed".
class PortraitClassifier {
  PortraitClassifier._(this._interpreter, this.labels, this._size, this._input,
      this._output, this.verified, this.letterbox);

  /// Path of the TFLite model file inside the app assets.
  static const String modelAsset = 'assets/models/portrait_classifier.tflite';

  /// Path of the text file listing class names, one per output.
  static const String labelsAsset = 'assets/models/portrait_labels.txt';

  /// Written by tools/train_monument.py --kind portrait. Missing = unverified.
  static const String infoAsset = 'assets/models/portrait_model_info.json';

  /// The TFLite runtime object that actually runs the model.
  final Interpreter _interpreter;

  /// Class names in the same order as the model outputs.
  final List<String> labels;

  /// See [infoAsset]. Unverified models only produce warnings.
  final bool verified;

  /// `"preprocess": "letterbox"` in the info file: keep the whole image,
  /// padded to a square.
  final bool letterbox;

  /// Denominations this model knows (from its labels).
  List<int> get knownDenominations =>
      [for (final l in labels) ?Portraits.denominationOf(l)];

  /// Side of the square model input in pixels (read from the model).
  final int _size;

  /// Input and output tensor descriptions (shape, type, quantisation).
  final Tensor _input;
  final Tensor _output;

  /// Loads the model, labels and optional info file. Returns null (never
  /// throws) if anything is missing or does not match.
  static Future<PortraitClassifier?> tryLoad() async {
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
        throw StateError('Unexpected portrait model input $inShape');
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
        // No info file: unverified model.
      }
      debugPrint('Portrait model loaded: input $inShape ${input.type}, '
          'labels $labels, verified $verified, letterbox $letterbox');
      return PortraitClassifier._(
          interpreter, labels, inShape[1], input, output, verified, letterbox);
    } on Object catch (e) {
      debugPrint('Portrait model not available: $e');
      return null;
    }
  }

  /// Quantised models take whole-number bytes instead of decimals.
  bool get _quantized => _input.type == TensorType.uint8;

  /// Classifies the portrait side in [pixels] (the front, RGBA).
  /// Returns the best class with its confidence (0-1).
  Future<PortraitPrediction> classify(RgbaImage pixels) async {
    // Step 1: build the model input in a background isolate. The preprocessing
    // is shared with the monument model (letterbox, x / 127.5 - 1).
    final size = _size, quantized = _quantized, pad = letterbox;
    final input = await Isolate.run(() => MonumentClassifier.teachableMachineInput(
        pixels, size, quantized,
        letterbox: pad));

    // Step 2: run the model into a byte buffer.
    final n = labels.length;
    final outBytes = Uint8List(_output.type == TensorType.uint8 ? n : n * 4);
    _interpreter.run(input, outBytes);

    // Step 3: turn the bytes into probabilities.
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
    return PortraitPrediction(
      label: labels[best],
      confidence: probs[best].clamp(0.0, 1.0),
      probabilities: {for (var i = 0; i < n; i++) labels[i]: probs[i]},
    );
  }

  /// Frees the model's memory. Call when finished.
  void close() => _interpreter.close();
}
