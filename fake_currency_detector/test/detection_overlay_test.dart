import 'package:fake_currency_detector/core/theme/app_theme.dart';
import 'package:fake_currency_detector/features/verification/data/models/note_analysis_model.dart';
import 'package:fake_currency_detector/features/verification/presentation/widgets/detection_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DetectionBoxModel box(int id, String label, double s, double l, double t) =>
      DetectionBoxModel(
          classId: id, label: label, score: s, left: l, top: t, right: l + 0.1, bottom: t + 0.1);

  testWidgets('renders boxes and per-class counts', (tester) async {
    final side = SideDetectionsModel(width: 2000, height: 900, boxes: [
      box(6, '50Rs Note', 0.94, 0, 0),
      box(10, 'security_lines', 0.81, 0.1, 0.2),
      box(10, 'security_lines', 0.42, 0.1, 0.35),
      box(12, 'serial_number', 0.9, 0.6, 0.1),
      box(12, 'serial_number', 0.88, 0.6, 0.8),
    ]);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: DetectionOverlayCard(side: 'FRONT', imagePath: null, detections: side),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.text('lines ×1 (+1 low)'), findsOneWidget);
    expect(find.text('serial ×2'), findsOneWidget);
    expect(find.text('50 Rs ×1'), findsOneWidget);
  });

  test('detections survive a JSON round trip', () {
    const m = NoteAnalysisModel(
      isBanknote: true,
      banknoteConfidence: 0.9,
      detections: {
        'front': SideDetectionsModel(width: 10, height: 5, boxes: [
          DetectionBoxModel(
              classId: 8, label: 'sbp_seal', score: 0.7, left: 0.1, top: 0.2, right: 0.3, bottom: 0.4),
        ]),
      },
    );
    final back = NoteAnalysisModel.fromJson(m.toJson());
    expect(back.detections['front']!.boxes.single.label, 'sbp_seal');
    expect(back.detections['front']!.width, 10);
  });
}
