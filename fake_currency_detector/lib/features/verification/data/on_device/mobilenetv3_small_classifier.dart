import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

/// Genuine/fake classifier for Rs 10, 20, 50, 100, 500 and 1,000
/// (`mobilenetv3small_final.tflite`). Never used for Rs 5,000.
///
/// - input  float32 [1, 224, 224, 3] RGB 0–255; MobileNetV3 preprocessing is
///   inside the model, so do not divide by 255.
/// - output float32 [1, 1] sigmoid `fake_probability`
///   (label mapping: 0 = genuine, 1 = fake).
///
/// Training reported 96.69% test accuracy (ROC AUC 99.61%). It is supporting
/// evidence only: 0.5 is the notebook's initial threshold, not a tuned one.
class MobileNetV3SmallClassifier {
  MobileNetV3SmallClassifier._(this._interpreter);

  static const String asset = 'assets/models/mobilenetv3small_final.tflite';
  static const String modelName =
      'MobileNetV3-Small · genuine/fake · Rs 10–1,000';

  /// Denominations this model was trained on.
  static const Set<int> denominations = {10, 20, 50, 100, 500, 1000};

  static bool supports(int? denomination) =>
      denomination != null && denominations.contains(denomination);

  final Interpreter _interpreter;

  static Future<MobileNetV3SmallClassifier> load() async {
    final interpreter = await Interpreter.fromAsset(
      asset,
      options: InterpreterOptions()..threads = 2,
    );
    final input = interpreter.getInputTensor(0).shape;
    final output = interpreter.getOutputTensor(0).shape;
    if (input.join(',') != '1,224,224,3' || output.join(',') != '1,1') {
      interpreter.close();
      throw StateError('Unexpected classifier tensors: in $input, out $output');
    }
    return MobileNetV3SmallClassifier._(interpreter);
  }

  /// Probability (0..1) that this side shows a fake note.
  double fakeProbability(Float32List rgb224) {
    final out = Uint8List(4);
    _interpreter.run(rgb224.buffer.asUint8List(), out);
    return ByteData.sublistView(out).getFloat32(0, Endian.little);
  }

  void close() => _interpreter.close();
}
