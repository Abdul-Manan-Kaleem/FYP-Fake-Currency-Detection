import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'result_screen.dart';
import '../services/ml_service.dart';

class ProcessingScreen extends StatefulWidget {
  final Uint8List frontImageBytes;
  final Uint8List backImageBytes;

  const ProcessingScreen({
    super.key,
    required this.frontImageBytes,
    required this.backImageBytes,
  });

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  int _currentStep = 0;
  final MLService _mlService = MLService();
  DetectionResult? _result;
  final List<String> _steps = [
    'Image Capture & Optimization',
    'Watermark Pattern Analysis',
    'Microprint & Hologram Verification',
    'Security Thread Check',
    'Final Scoring'
  ];

  @override
  void initState() {
    super.initState();
    _simulateProcess();
  }

  void _simulateProcess() async {
    // 1. Initialize ML and run inference in the background
    await _mlService.initialize();
    
    final frontResult = await _mlService.analyzeImage(widget.frontImageBytes);
    final backResult = await _mlService.analyzeImage(widget.backImageBytes);
    
    // Check if ML Kit flagged them as NOT currency
    if ((frontResult != null && !frontResult.isCurrencyNote) || 
        (backResult != null && !backResult.isCurrencyNote)) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Invalid Image Detected', style: TextStyle(color: Colors.red)),
            content: const Text('One or both of the images do not appear to be valid currency notes. Please make sure the note is clearly visible in the frame and try again.'),
            backgroundColor: Theme.of(context).colorScheme.surface,
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // dismiss dialog
                  Navigator.of(context).pop(); // go back to scanner
                },
                child: const Text('Try Again'),
              ),
            ],
          ),
        );
      }
      return;
    }
    
    if (frontResult != null && backResult != null) {
      // Instead of a strict &&, we average the real and fake probabilities
      // This prevents a single 'confused' scan (e.g. back of the note) from ruining the result
      final avgRealProb = (frontResult.realProbability + backResult.realProbability) / 2;
      final avgFakeProb = (frontResult.fakeProbability + backResult.fakeProbability) / 2;
      
      final isAuthentic = avgRealProb > avgFakeProb;
      final confidenceScore = (isAuthentic ? avgRealProb : avgFakeProb) * 100.0;
      
      _result = DetectionResult(
        isAuthentic: isAuthentic, 
        confidenceScore: confidenceScore,
        realProbability: avgRealProb,
        fakeProbability: avgFakeProb,
      );
    } else {
      // Fallback if inference fails
      _result = DetectionResult(isAuthentic: false, confidenceScore: 0.0);
    }

    // 2. Play UI animation
    for (int i = 0; i < _steps.length; i++) {
      // Simulate time taken for each processing step
      await Future.delayed(const Duration(milliseconds: 1000));
      if (mounted) {
        setState(() {
          _currentStep = i + 1;
        });
      }
    }
    
    // Process finished, pause slightly then navigate to Result
    if (mounted) {
      await Future.delayed(const Duration(seconds: 1));
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ResultScreen(
            isAuthentic: _result?.isAuthentic ?? false,
            confidenceScore: _result?.confidenceScore ?? 0.0,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _mlService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Analyzing Currency'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Circular Progress Bar
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 160,
                    height: 160,
                    child: CircularProgressIndicator(
                      value: _currentStep == 0 ? null : _currentStep / _steps.length,
                      strokeWidth: 10,
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _currentStep == _steps.length ? Colors.green : Theme.of(context).colorScheme.primary,
                      ),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Text(
                    '${((_currentStep / _steps.length) * 100).toInt()}%',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            // Checklist
            Expanded(
              child: ListView.builder(
                itemCount: _steps.length,
                itemBuilder: (context, index) {
                  final isCompleted = _currentStep > index;
                  final isCurrent = _currentStep == index;
                  
                  // Logic to simulate feature failures if the result is Fake
                  bool isFailed = false;
                  if (isCompleted && _result != null && !_result!.isAuthentic) {
                    // Fail Watermark (1), Microprint (2), and Security Thread (3)
                    if (index >= 1 && index <= 3) {
                      isFailed = true;
                    }
                  }
                  
                  final isPassed = isCompleted && !isFailed;
                  
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOut,
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isFailed
                          ? Colors.red.withOpacity(0.1)
                          : isPassed
                              ? Colors.green.withOpacity(0.1)
                              : isCurrent
                                  ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                                  : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isFailed
                            ? Colors.red
                            : isPassed
                                ? Colors.green
                                : isCurrent
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (Widget child, Animation<double> animation) {
                            return ScaleTransition(scale: animation, child: child);
                          },
                          child: isFailed
                              ? const Icon(Icons.cancel, color: Colors.red, size: 28, key: ValueKey('failed'))
                              : isPassed
                                  ? const Icon(Icons.check_circle, color: Colors.green, size: 28, key: ValueKey('done'))
                              : isCurrent
                                  ? SizedBox(
                                      key: const ValueKey('loading'),
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    )
                                  : Icon(
                                      Icons.radio_button_unchecked, 
                                      color: Colors.white.withOpacity(0.3), 
                                      size: 28, 
                                      key: const ValueKey('pending'),
                                    ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            _steps[index],
                            style: TextStyle(
                              color: isFailed
                                  ? Colors.red
                                  : isPassed
                                      ? Colors.green
                                      : isCurrent
                                          ? Colors.white
                                          : Colors.white.withOpacity(0.5),
                              fontWeight: isCompleted || isCurrent ? FontWeight.bold : FontWeight.normal,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
