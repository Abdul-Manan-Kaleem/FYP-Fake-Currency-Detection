import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyp_fake_currency_detection/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const FakeCurrencyDetectorApp());

    // Wait for the splash screen animations if any.
    await tester.pumpAndSettle();

    // Verify some text on the screen.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
