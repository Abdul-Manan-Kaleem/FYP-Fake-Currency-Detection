import 'package:flutter/material.dart';
import 'main_navigation.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _onboardingData = [
    {
      'title': 'Precision Camera Scanning',
      'description': 'Align your currency within the frame for optimal accuracy. Our engine captures ultra-high-resolution details in milliseconds.',
      'icon': Icons.camera_enhance_rounded,
      'color1': const Color(0xFF00D2FF),
      'color2': const Color(0xFF3A7BD5),
    },
    {
      'title': 'AI Security Checks',
      'description': 'Automatically authenticates microprints, UV features, security threads, and watermarks simultaneously against our real-time database.',
      'icon': Icons.security_rounded,
      'color1': const Color(0xFFFF512F),
      'color2': const Color(0xFFDD2476),
    },
    {
      'title': 'Instant Veracity Results',
      'description': 'View an interactive 3D map of the scanned note alongside a definitive confidence score. Fake currency has nowhere to hide.',
      'icon': Icons.analytics_rounded,
      'color1': const Color(0xFF11998E),
      'color2': const Color(0xFF38EF7D),
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToHome() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const MainNavigationScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemCount: _onboardingData.length,
            itemBuilder: (context, index) {
              final data = _onboardingData[index];
              return Padding(
                padding: const EdgeInsets.all(40.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      height: 240,
                      width: 240,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [data['color1'], data['color2']],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(color: data['color1'].withValues(alpha: 0.4), blurRadius: 40, spreadRadius: 10),
                        ],
                      ),
                      child: Icon(data['icon'], size: 100, color: Colors.white),
                    ),
                    const SizedBox(height: 60),
                    Text(
                      data['title'],
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, height: 1.2),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      data['description'],
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.white.withValues(alpha: 0.7), height: 1.5),
                    ),
                  ],
                ),
              );
            },
          ),
          Positioned(
            top: 50,
            right: 20,
            child: TextButton(
              onPressed: _goToHome,
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              child: const Text('Skip', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: List.generate(
                      _onboardingData.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.only(right: 8),
                        height: 8,
                        width: _currentPage == index ? 24 : 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index ? _onboardingData[_currentPage]['color1'] : Colors.white24,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      if (_currentPage == _onboardingData.length - 1) {
                        _goToHome();
                      } else {
                        _pageController.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.ease);
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_onboardingData[_currentPage]['color1'], _onboardingData[_currentPage]['color2']],
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(color: _onboardingData[_currentPage]['color1'].withValues(alpha: 0.4), blurRadius: 15, offset: const Offset(0, 5)),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _currentPage == _onboardingData.length - 1 ? 'Get Started' : 'Next',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
