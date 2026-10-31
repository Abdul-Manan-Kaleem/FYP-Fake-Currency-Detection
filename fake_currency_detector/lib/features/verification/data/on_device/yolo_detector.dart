import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import 'yolo_decoder.dart';

/// Runs the exported Ultralytics YOLO11s TFLite model.
///
/// Verified tensor contract (see README "YOLO11s integration"):
/// - input  float32 [1, 3, 640, 640]: channels-first RGB 0–1, letterboxed
/// - output float32 [1, 17, 8400]: raw cx, cy, w, h + 13 sigmoid class
///   scores per anchor, no NMS in graph
class YoloDetector {
  YoloDetector._(this._interpreter, this._isolate);

  static const String asset = 'assets/models/yolo11s_currency.tflite';

  /// Boxes come out divided by the input size (`_NormalizeCoords` in graph).
  static const bool normalizedBoxes = true;

  final Interpreter _interpreter;
  final IsolateInterpreter _isolate;

  static Future<YoloDetector> load() async {
    final interpreter = await Interpreter.fromAsset(
      asset,
      options: InterpreterOptions()..threads = 4,
    );
    final input = interpreter.getInputTensor(0).shape;
    final output = interpreter.getOutputTensor(0).shape;
    const expectedOut = [1, 4 + YoloDecoder.numClasses, YoloDecoder.anchors];
    if (input.join(',') != '1,3,640,640' ||
        output.join(',') != expectedOut.join(',')) {
      interpreter.close();
      throw StateError('Unexpected YOLO tensors: in $input, out $output');
    }
    final isolate = await IsolateInterpreter.create(address: interpreter.address);
    return YoloDetector._(interpreter, isolate);
  }

  /// Raw head output for one letterboxed CHW image. Calls must not overlap:
  /// IsolateInterpreter drops a call made while it is busy.
  Future<Float32List> run(Float32List chw) {
    // Queue calls: a scan can start (right after capture) while another is
    // still running, and IsolateInterpreter would silently drop it.
    final next = _queue.then((_) async {
      final out =
          Uint8List((4 + YoloDecoder.numClasses) * YoloDecoder.anchors * 4);
      await _isolate.run(chw.buffer.asUint8List(), out);
      return out.buffer.asFloat32List();
    });
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _queue = Future.value();

  /// Post-NMS detections plus each class's highest raw score.
  Future<(List<YoloDetection>, List<double>)> detect(Float32List chw) async {
    final raw = await run(chw);
    return (
      YoloDecoder.decode(raw, normalized: normalizedBoxes),
      YoloDecoder.classMax(raw),
    );
  }

  Future<void> close() async {
    await _isolate.close();
    _interpreter.close();
  }
}
