import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

/// Rs 5,000 genuine/counterfeit classifier from `mobilenetv3_pkr5000.pth`
/// (torchvision MobileNetV3-Large, 2-way head), converted to TFLite.
///
/// Conversion (PyTorch → ONNX → onnx2tf, float32) wraps the trained network
/// as `softmax(model((x − mean·255) / (std·255)))`, so:
/// - input  float32 [1, 224, 224, 3] RGB 0–255, resized like torchvision
///   `Resize((224, 224))` (see ImagePreprocessor.pilBilinearRgb)
/// - output float32 [1, 2] probabilities in checkpoint class order
///
/// Verified against PyTorch on the same inputs: max |Δprob| 2.4e-7,
/// same class 8/8.
class Pkr5000CounterfeitClassifier {
  Pkr5000CounterfeitClassifier._(this._interpreter);

  static const String asset = 'assets/models/mobilenetv3_pkr5000_counterfeit.tflite';
  static const String modelName = 'MobileNetV3-Large · genuine/counterfeit · Rs 5,000 only';

  /// `class_to_idx` saved in the checkpoint: {'counterfeit': 0, 'genuine': 1}.
  static const List<String> classNames = ['counterfeit', 'genuine'];
  static const int counterfeitIndex = 0;

  final Interpreter _interpreter;

  static Future<Pkr5000CounterfeitClassifier> load() async {
    final interpreter = await Interpreter.fromAsset(
      asset,
      options: InterpreterOptions()..threads = 4,
    );
    final input = interpreter.getInputTensor(0).shape;
    final output = interpreter.getOutputTensor(0).shape;
    if (input.join(',') != '1,224,224,3' || output.join(',') != '1,2') {
      interpreter.close();
      throw StateError('Unexpected classifier tensors: in $input, out $output');
    }
    return Pkr5000CounterfeitClassifier._(interpreter);
  }

  /// Probability that this side shows a counterfeit Rs 5,000 note.
  double counterfeitProbability(Float32List rgb224) {
    final out = Uint8List(2 * 4);
    _interpreter.run(rgb224.buffer.asUint8List(), out);
    return ByteData.sublistView(out)
        .getFloat32(counterfeitIndex * 4, Endian.little);
  }

  void close() => _interpreter.close();
}
