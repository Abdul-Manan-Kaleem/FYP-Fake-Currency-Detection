/// Rs 5,000 "synthetic alteration" classifier (MobileNetV3-Large).
///
/// In: a 224x224 RGB tensor (a block of numbers). Out: probability (0-1)
/// that the note was altered/fake. Model file:
/// `assets/models/rs5000_mobilenetv3large.tflite`.
library;

import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

/// Wraps `rs5000_mobilenetv3large.tflite`: MobileNetV3-Large with a sigmoid
/// head that outputs the probability that a Rs 5000 note is altered/fake.
///
/// Input: float32 [1, 224, 224, 3] RGB in 0–255 (the model rescales itself).
/// Output: float32 [1, 1] altered probability.
class Rs5000AnomalyClassifier {
  Rs5000AnomalyClassifier._(this._interpreter);

  /// Path of the TFLite model file inside the app assets.
  static const String asset = 'assets/models/rs5000_mobilenetv3large.tflite';

  /// Name shown in results.
  static const String modelName =
      'MobileNetV3-Large · synthetic alteration · Rs 5,000 only';

  /// The only denomination (rupees) this model is for.
  static const int denomination = 5000;

  /// The TFLite runtime object that actually runs the model.
  final Interpreter _interpreter;

  /// Loads the model (4 CPU threads) and checks input is [1,224,224,3] and
  /// output is [1,1]; throws a StateError otherwise.
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
    // The interpreter works on raw bytes: 4 bytes out = one float32.
    final out = Uint8List(4);
    _interpreter.run(rgb224.buffer.asUint8List(), out);
    return ByteData.sublistView(out).getFloat32(0, Endian.little);
  }

  /// Frees the model's memory. Call when finished.
  void close() => _interpreter.close();
}
