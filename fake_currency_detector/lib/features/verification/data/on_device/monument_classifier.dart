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

  final String label;
  final double confidence;
  final Map<String, double> probabilities;

  int? get denomination => Monuments.denominationOf(label);
}

/// Optional Teachable Machine (MobileNet) image classifier for the back-side
/// monument. Bundled as `assets/models/monument_classifier.tflite` +
/// `assets/models/monument_labels.txt`. When the files are missing,
/// [tryLoad] returns null and the monument check reports "not installed".
class MonumentClassifier {
  MonumentClassifier._(this._interpreter, this.labels, this._size, this._input,
      this._output, this.verified, this.letterbox);

  static const String modelAsset = 'assets/models/monument_classifier.tflite';
  static const String labelsAsset = 'assets/models/monument_labels.txt';

  /// Written by tools/train_monument.py: {"verified": true/false, ...}.
  /// Missing → unverified.
  static const String infoAsset = 'assets/models/monument_model_info.json';

  final Interpreter _interpreter;
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
  final int _size;
  final Tensor _input;
  final Tensor _output;

  static Future<MonumentClassifier?> tryLoad() async {
    try {
      final labels = Monuments.parseLabels(await rootBundle.loadString(labelsAsset));
      final interpreter = await Interpreter.fromAsset(
        modelAsset,
        options: InterpreterOptions()..threads = 4,
      );
      final input = interpreter.getInputTensor(0);
      final output = interpreter.getOutputTensor(0);
      final inShape = input.shape, outShape = output.shape;
      if (inShape.length != 4 || inShape[1] != inShape[2] || inShape[3] != 3) {
        throw StateError('Unexpected monument model input $inShape');
      }
      if (outShape.last != labels.length) {
        throw StateError('Model has ${outShape.last} outputs but '
            '${labels.length} labels');
      }
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

  bool get _quantized => _input.type == TensorType.uint8;

  Future<MonumentPrediction> classify(RgbaImage pixels) async {
    final size = _size, quantized = _quantized, pad = letterbox;
    final input = await Isolate.run(
        () => teachableMachineInput(pixels, size, quantized, letterbox: pad));

    final n = labels.length;
    final outBytes = Uint8List(_output.type == TensorType.uint8 ? n : n * 4);
    _interpreter.run(input, outBytes);

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
  static Uint8List teachableMachineInput(
    RgbaImage pixels,
    int size,
    bool quantized, {
    bool letterbox = false,
  }) {
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

  void close() => _interpreter.close();
}
