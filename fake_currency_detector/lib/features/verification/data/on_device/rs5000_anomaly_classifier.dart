import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

/// Wraps `rs5000_mobilenetv3large.tflite`: MobileNetV3-Large with a sigmoid
/// head that outputs the probability that a Rs 5000 note is altered/fake.
///
/// Input: float32 [1, 224, 224, 3] RGB in 0–255 (the model rescales itself).
/// Output: float32 [1, 1] altered probability.
class Rs5000AnomalyClassifier {
  Rs5000AnomalyClassifier._(this._interpreter);

  static const String asset = 'assets/models/rs5000_mobilenetv3large.tflite';
  static const String modelName =
      'MobileNetV3-Large · synthetic alteration · Rs 5,000 only';
  static const int denomination = 5000;

  final Interpreter _interpreter;

  static Future<Rs5000AnomalyClassifier> load() async {
    final interpreter = await Interpreter.fromAsset(
      asset,
      options: InterpreterOptions()..threads = 4,
    );
    final input = interpreter.getInputTensor(0).shape;
    final output = interpreter.getOutputTensor(0).shape;
    if (input.length != 4 || input[1] != 224 || input[2] != 224 || input[3] != 3) {
      throw StateError('Unexpected model input shape $input');
    }
    if (output.length != 2 || output[1] != 1) {
      throw StateError('Unexpected model output shape $output');
    }
    return Rs5000AnomalyClassifier._(interpreter);
  }

  /// Returns the altered/fake probability (0..1) for one side.
  double predict(Float32List rgb224) {
    final out = Uint8List(4);
    _interpreter.run(rgb224.buffer.asUint8List(), out);
    return ByteData.sublistView(out).getFloat32(0, Endian.little);
  }

  void close() => _interpreter.close();
}
