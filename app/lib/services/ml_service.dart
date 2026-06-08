import 'dart:typed_data';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

class DetectionResult {
  final bool isAuthentic;
  final double confidenceScore;
  final double realProbability;
  final double fakeProbability;
  final bool isCurrencyNote;

  DetectionResult({
    required this.isAuthentic, 
    required this.confidenceScore,
    this.realProbability = 0.0,
    this.fakeProbability = 0.0,
    this.isCurrencyNote = true,
  });
}

class MLService {
  Interpreter? _interpreter;
  final int _inputSize = 224;

  Future<void> initialize() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/currency_model.tflite');
      print('Model loaded successfully');
    } catch (e) {
      print('Failed to load model: $e');
    }
  }

  Future<DetectionResult?> analyzeImage(Uint8List imageBytes) async {
    if (_interpreter == null) {
      print('Interpreter not initialized');
      return null;
    }

    try {
      // 1. Google ML Kit: Currency / Document Pre-Check
      final tempFile = File('${Directory.systemTemp.path}/temp_img_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(imageBytes);
      
      final inputImage = InputImage.fromFile(tempFile);
      final ImageLabelerOptions options = ImageLabelerOptions(confidenceThreshold: 0.5);
      final imageLabeler = ImageLabeler(options: options);
      
      final List<ImageLabel> labels = await imageLabeler.processImage(inputImage);
      imageLabeler.close();
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      
      bool isCurrency = false;
      final validKeywords = ['money', 'cash', 'currency', 'banknote', 'paper', 'document', 'text', 'rectangle'];
      
      for (ImageLabel label in labels) {
        final text = label.label.toLowerCase();
        if (validKeywords.any((keyword) => text.contains(keyword))) {
          isCurrency = true;
          break;
        }
      }
      
      if (!isCurrency) {
        return DetectionResult(
          isAuthentic: false, 
          confidenceScore: 0.0, 
          isCurrencyNote: false
        );
      }

      // 2. TFLite Inference
      // Decode image
      img.Image? decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) return null;

      // Resize image to 224x224
      img.Image resizedImage = img.copyResize(decodedImage, width: _inputSize, height: _inputSize);

      // Convert to float32 [1, 224, 224, 3] and feed raw 0-255 values
      // The model was trained with tf.keras.applications.imagenet_utils.preprocess_input
      // which is baked into the model graph as symbolic layers.
      var input = List.generate(
        1,
        (i) => List.generate(
          _inputSize,
          (y) => List.generate(
            _inputSize,
            (x) {
              final pixel = resizedImage.getPixel(x, y);
              return [
                pixel.r.toDouble(),
                pixel.g.toDouble(),
                pixel.b.toDouble()
              ];
            },
          ),
        ),
      );

      // Output array [1, 2] since we have 2 classes (0: fake, 1: real)
      var output = List.generate(1, (i) => List.filled(2, 0.0));

      // Run inference
      _interpreter!.run(input, output);

      // Interpret results
      final probabilities = output[0];
      final fakeProb = probabilities[0];
      final realProb = probabilities[1];

      print('--- ML Inference Results ---');
      print('Fake Probability: ${(fakeProb * 100).toStringAsFixed(2)}%');
      print('Real Probability: ${(realProb * 100).toStringAsFixed(2)}%');

      final isAuthentic = realProb > fakeProb;
      final confidence = isAuthentic ? realProb : fakeProb;

      return DetectionResult(
        isAuthentic: isAuthentic,
        confidenceScore: confidence * 100.0,
        realProbability: realProb,
        fakeProbability: fakeProb,
      );
    } catch (e) {
      print('Error running ML analysis: $e');
      return null;
    }
  }

  void dispose() {
    _interpreter?.close();
  }
}
