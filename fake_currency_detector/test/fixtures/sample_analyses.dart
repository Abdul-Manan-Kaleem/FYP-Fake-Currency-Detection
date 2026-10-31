// Detector outputs used to pin the engine's scoring in tests.
import 'package:fake_currency_detector/features/verification/data/models/note_analysis_model.dart';

enum SampleAnalysis {
  authentic5000('Authentic Rs 5000', '96% Confidence'),
  mismatchedSerials('Counterfeit: Mismatched Serials', '32% Confidence'),
  missingBackSeals('Counterfeit: Missing Back Seals', '58% Confidence'),
  blurry('Blurry: Retake Required', '0% Confidence'),
  notBanknote('Not a Banknote', 'Triggers Alert Modal');

  const SampleAnalysis(this.title, this.subtitle);

  final String title;
  final String subtitle;

  String get label => '$title ($subtitle)';

  NoteAnalysisModel get analysis => switch (this) {
        authentic5000 => _authentic5000,
        mismatchedSerials => _mismatchedSerials,
        missingBackSeals => _missingBackSeals,
        blurry => _blurry,
        notBanknote => _notBanknote,
      };
}

const _sharp = ImageQualityModel(blurScore: 0.07, glareScore: 0.05, brightness: 0.56);

// Confidences below are tuned so the VerificationEngine produces the
// percentages advertised in each scenario label (see test/).

const _authentic5000 = NoteAnalysisModel(
  isBanknote: true,
  banknoteConfidence: 0.99,
  front: SideDetectionModel(
    quality: _sharp,
    denomination: 5000,
    denominationConfidence: 0.93,
    sbpSeals: FeatureDetectionModel(count: 1, confidence: 0.80),
    securityThreads: FeatureDetectionModel(count: 1, confidence: 0.80),
    securityLines: FeatureDetectionModel(count: 0, confidence: 0.90),
    securityDots: FeatureDetectionModel(count: 3, confidence: 0.87),
    printedYear: PrintedYearModel(detected: true, value: '2022', confidence: 0.85),
    serialNumbers: [
      SerialReadModel(text: 'AK4718263', confidence: 0.89),
      SerialReadModel(text: 'AK4718263', confidence: 0.88),
    ],
  ),
  back: SideDetectionModel(
    quality: _sharp,
    denomination: 5000,
    denominationConfidence: 0.92,
    sbpSeals: FeatureDetectionModel(count: 3, confidence: 0.86),
    securityThreads: FeatureDetectionModel(count: 1, confidence: 0.88),
  ),
  anomaly: AnomalyModel(anomalyScore: 0.16, model: 'MobileNetV3-Large'),
);

const _mismatchedSerials = NoteAnalysisModel(
  isBanknote: true,
  banknoteConfidence: 0.97,
  front: SideDetectionModel(
    quality: _sharp,
    denomination: 1000,
    denominationConfidence: 0.95,
    sbpSeals: FeatureDetectionModel(count: 1, confidence: 0.84),
    securityThreads: FeatureDetectionModel(count: 1, confidence: 0.82),
    securityLines: FeatureDetectionModel(count: 0, confidence: 0.92),
    securityDots: FeatureDetectionModel(count: 2, confidence: 0.90),
    printedYear: PrintedYearModel(detected: true, value: '2019', confidence: 0.88),
    serialNumbers: [
      SerialReadModel(text: 'GH3381902', confidence: 0.94),
      SerialReadModel(text: 'GH3381S07', confidence: 0.92),
    ],
  ),
  back: SideDetectionModel(
    quality: _sharp,
    denomination: 1000,
    denominationConfidence: 0.94,
    sbpSeals: FeatureDetectionModel(count: 3, confidence: 0.90),
    securityThreads: FeatureDetectionModel(count: 1, confidence: 0.88),
  ),
  anomaly: AnomalyModel(anomalyScore: 0.31, model: 'MobileNetV3-Large'),
);

const _missingBackSeals = NoteAnalysisModel(
  isBanknote: true,
  banknoteConfidence: 0.98,
  front: SideDetectionModel(
    quality: _sharp,
    denomination: 500,
    denominationConfidence: 0.93,
    sbpSeals: FeatureDetectionModel(count: 1, confidence: 0.90),
    securityThreads: FeatureDetectionModel(count: 1, confidence: 0.88),
    securityLines: FeatureDetectionModel(count: 0, confidence: 0.91),
    securityDots: FeatureDetectionModel(count: 1, confidence: 0.89),
    printedYear: PrintedYearModel(detected: true, value: '2021', confidence: 0.87),
    serialNumbers: [
      SerialReadModel(text: 'RQ6604175', confidence: 0.93),
      SerialReadModel(text: 'RQ6604175', confidence: 0.92),
    ],
  ),
  back: SideDetectionModel(
    quality: _sharp,
    denomination: 500,
    denominationConfidence: 0.92,
    sbpSeals: FeatureDetectionModel(count: 1, confidence: 0.84),
    securityThreads: FeatureDetectionModel(count: 1, confidence: 0.86),
  ),
  anomaly: AnomalyModel(anomalyScore: 0.22, model: 'MobileNetV3-Large'),
);

const _blurry = NoteAnalysisModel(
  isBanknote: true,
  banknoteConfidence: 0.81,
  front: SideDetectionModel(
    quality: ImageQualityModel(blurScore: 0.83, glareScore: 0.71, brightness: 0.62),
    denomination: 100,
    denominationConfidence: 0.41,
    sbpSeals: FeatureDetectionModel(count: 0, confidence: 0.22),
    serialNumbers: [
      SerialReadModel(text: '', confidence: 0.12),
      SerialReadModel(text: '', confidence: 0.09),
    ],
  ),
  back: SideDetectionModel(
    quality: ImageQualityModel(blurScore: 0.66, glareScore: 0.18, brightness: 0.48),
    denomination: 100,
    denominationConfidence: 0.52,
    sbpSeals: FeatureDetectionModel(count: 2, confidence: 0.31),
  ),
);

const _notBanknote = NoteAnalysisModel(
  isBanknote: false,
  banknoteConfidence: 0.03,
);
