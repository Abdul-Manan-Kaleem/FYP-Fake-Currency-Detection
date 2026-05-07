import 'package:flutter/material.dart';
import 'result_screen.dart';
class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  int _currentStep = 0;
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
    for (int i = 0; i < _steps.length; i++) {
      // Simulate time taken for each processing step
      await Future.delayed(const Duration(milliseconds: 1500));
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
        MaterialPageRoute(builder: (context) => const ResultScreen()),
      );
    }
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
                  
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOut,
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? Colors.green.withOpacity(0.1)
                          : isCurrent
                              ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                              : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isCompleted
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
                          child: isCompleted
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
                              color: isCompleted
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
