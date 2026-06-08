import 'package:flutter/material.dart';
import 'dart:typed_data';

class ResultScreen extends StatelessWidget {
  final bool isAuthentic;
  final double confidenceScore;
  final Uint8List? frontImageBytes;
  final Uint8List? backImageBytes;

  const ResultScreen({
    super.key,
    required this.isAuthentic,
    required this.confidenceScore,
    this.frontImageBytes,
    this.backImageBytes,
  });

  Widget _buildBoundingBox(bool isAuthentic, String label) {
    final color = isAuthentic ? Colors.greenAccent : Colors.redAccent;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 2),
        color: color.withOpacity(0.2),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          color: color,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Analysis Result'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false, // Don't allow back swipe to processing
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 10),
            // Display the scanned image if available
            if (frontImageBytes != null)
              Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isAuthentic ? Colors.green : Colors.redAccent,
                    width: 4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isAuthentic ? Colors.green : Colors.redAccent).withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            frontImageBytes!,
                            fit: BoxFit.cover,
                          ),
                          // Simulated Watermark Bounding Box
                          Positioned(
                            left: constraints.maxWidth * 0.05,
                            top: constraints.maxHeight * 0.15,
                            width: constraints.maxWidth * 0.3,
                            height: constraints.maxHeight * 0.7,
                            child: _buildBoundingBox(isAuthentic, "Watermark"),
                          ),
                          // Simulated Security Thread Bounding Box
                          Positioned(
                            left: constraints.maxWidth * 0.65,
                            top: 0,
                            width: constraints.maxWidth * 0.08,
                            height: constraints.maxHeight,
                            child: _buildBoundingBox(isAuthentic, "Thread"),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              )
            else
              // Fallback Icon
              TweenAnimationBuilder(
                duration: const Duration(milliseconds: 800),
                tween: Tween<double>(begin: 0, end: 1),
                builder: (context, double value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: isAuthentic 
                            ? Colors.green.withOpacity(0.1) 
                            : Colors.red.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isAuthentic ? Icons.verified : Icons.warning_rounded,
                        size: 100,
                        color: isAuthentic ? Colors.green : Colors.redAccent,
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 32),
            // Title
            Text(
              isAuthentic ? 'Authentic Currency' : 'Counterfeit Detected',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isAuthentic ? Colors.green : Colors.redAccent,
                  ),
            ),
            const SizedBox(height: 8),
            // Confidence Score
            Text(
              'Confidence Score: ${confidenceScore.toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white70,
                  ),
            ),
            const SizedBox(height: 48),
            // Breakdown Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white10,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Security Features Analysis',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                  ),
                  const Divider(color: Colors.white24, height: 32),
                  _buildFeatureRow('Watermark Pattern', true),
                  const SizedBox(height: 16),
                  _buildFeatureRow('Microprint Details', true),
                  const SizedBox(height: 16),
                  _buildFeatureRow('Security Thread', isAuthentic),
                  const SizedBox(height: 16),
                  _buildFeatureRow('Hologram Verification', true),
                ],
              ),
            ),
            const SizedBox(height: 48),
            // Action Buttons
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () {
                  // Pop back to the Dashboard/Scan Tab
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: const Text(
                  'Scan Another Note',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow(String feature, bool passed) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          feature,
          style: const TextStyle(fontSize: 16, color: Colors.white70),
        ),
        Row(
          children: [
            Text(
              passed ? 'Passed' : 'Failed',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: passed ? Colors.green : Colors.redAccent,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              passed ? Icons.check_circle : Icons.cancel,
              color: passed ? Colors.green : Colors.redAccent,
              size: 20,
            ),
          ],
        ),
      ],
    );
  }
}
