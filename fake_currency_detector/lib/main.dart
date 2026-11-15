/// App entry point for the Pakistani Currency Note Screening System.
///
/// Sets up the phone screen (portrait only, dark status bar) and starts the
/// app with the capture screen as the first page.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/scanner/presentation/screens/capture_screen.dart';

/// First function that runs when the app starts.
void main() {
  // Step 1: Make sure Flutter is ready before we talk to the phone system.
  WidgetsFlutterBinding.ensureInitialized();
  // Step 2: Lock the screen to upright portrait mode.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Step 3: Transparent status bar and dark navigation bar with light icons,
  // so they blend with the dark app theme.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.onyxDeep,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  // Step 4: Start the app. ProviderScope is needed by Riverpod (the state
  // management library) so screens can share controllers.
  runApp(const ProviderScope(child: FakeCurrencyDetectorApp()));
}

/// Root widget of the app: sets the title, the dark theme and the home page.
class FakeCurrencyDetectorApp extends StatelessWidget {
  const FakeCurrencyDetectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fake Currency Detector',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const CaptureScreen(),
    );
  }
}
