import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FakeCurrencyDetectorApp());
}

class FakeCurrencyDetectorApp extends StatelessWidget {
  const FakeCurrencyDetectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fake Currency Detector',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00D2FF),
          brightness: Brightness.dark,
          surface: const Color(0xFF151C2C),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -1.0),
          titleLarge: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
      ),
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
