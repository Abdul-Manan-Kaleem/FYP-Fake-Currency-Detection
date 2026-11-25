# Code map: "show me where this is in the code"

All paths are inside `fake_currency_detector/lib/` (open the project in Android Studio and press **Ctrl+Shift+N**
to jump to a file, **Ctrl+G** to jump to a line, **Ctrl+Shift+F** to search any text you see in the app).
Line numbers are for the final version of the code; if a file was edited later, search for the name instead.

## 0. How a scan flows through the code (say this first)

```
capture_screen.dart  ->  capture_controller.dart  ->  note_capture_service.dart      (take 2 photos, check side)
        |
analyzing_screen.dart -> verification_controller.dart -> verify_banknote_use_case.dart
        |
on_device_currency_verification_repository.dart  (runs the models: THE INTEGRATION FILE)
        |   YOLO11s, OCR, monument + portrait classifiers, Rs 5,000 CNNs
        v
NoteAnalysisModel  (the evidence: boxes, counts, text, scores)
        |
verification_engine.dart  (the rules + the score: REAL or FAKE)
        |
results_screen.dart  (verdict, percentage, features list)   +   scan_history_database.dart (saved)
```

## 1. "Where is this button / screen in the app?"

| What the examiner points at | File : line |
|---|---|
| App starts here (`main`) and first screen | `main.dart:16`, `main.dart:48` (`home: CaptureScreen`) |
| **SCAN FRONT / SCAN BACK** button | `features/scanner/presentation/screens/capture_screen.dart:290` |
| **Upload from gallery** | `capture_screen.dart:297` |
| **History** button (top right) | `capture_screen.dart:124` |
| **Enhance photos** switch | `capture_screen.dart:530` (logic: `capture_controller.dart:194`) |
| **ANALYZE BANKNOTE** button | `capture_screen.dart:585` |
| Flip-the-note screen, **SCAN BACK** | `capture_screen.dart:437` |
| Retake button on a photo card | `features/scanner/presentation/widgets/holo_preview_card.dart:167` |
| Analysing animation screen | `features/verification/presentation/screens/analyzing_screen.dart:39` |
| **Results screen** (everything after analysis) | `features/verification/presentation/screens/results_screen.dart:48` |
| **The percentage score (big number)** | `features/verification/presentation/widgets/confidence_gauge.dart:71` (used at `results_screen.dart:120`) |
| **REAL / FAKE badge** | `features/verification/presentation/widgets/verdict_badge.dart:93` (used at `results_screen.dart:129`) |
| Red "fake" banner (photocopy / monument / portrait) | `results_screen.dart:142-154` |
| **SECURITY FEATURES list** (dots, lines, thread, seals, serials, year, **portrait**, **monument**) | `features/verification/presentation/widgets/security_features_card.dart` (rows at `:80-88`: dots, lines, thread, seals, serials, year, portrait `:87`, monument `:88`), used at `results_screen.dart:175` |
| INSPECTION CHECKLIST / ANALYST NOTES | `results_screen.dart:217`, `results_screen.dart:241` |
| **SCANNED NOTE** (the two photos at the bottom) | `results_screen.dart:257` |
| **SCAN HISTORY screen** and CSV share button | `features/history/presentation/history_screen.dart:40`, `:61` |

## 2. "Where are the models integrated?" (the integration code)

**Main integration file:** `features/verification/data/repositories/on_device_currency_verification_repository.dart`

| Step | Line | What it does |
|---|---|---|
| `_scan` (one photo) | 173 | Prepares the photo, runs YOLO11s (`:179`), runs the monument model (`:185`) |
| `checkSide` | 219 | Quick check right after capture: front or back, which note |
| `analyzeBanknote` | 268 | The full analysis of both sides |
| Text reading (serials, year) | 372 | Google ML Kit `TextRecognizer` |
| Dots / lines counting | 470-478 | `ImagePreprocessor.countMarks` (original pixels, no enhancement) |
| Rs 5,000 extras (microprint) | 513 | Full-resolution crops |
| Rs 5,000 alteration CNN | 548 | `Rs5000AnomalyClassifier.load` |
| Rs 5,000 genuine/counterfeit CNN | 563 | `Pkr5000CounterfeitClassifier.load` |
| Quaid-e-Azam portrait | 609-614 | `PortraitClassifier.tryLoad()` then `classify` |
| Build the evidence bundle | 639 | `NoteAnalysisModel(...)` |

**One file per model** (`features/verification/data/on_device/`):

| Model | File : loading line | Model file in `assets/models/` |
|---|---|---|
| YOLO11s detector (13 classes) | `yolo_detector.dart:25` (asset), `:40` (load), `:78` (detect) | `yolo11s_currency.tflite` |
| YOLO output decoder + NMS | `yolo_decoder.dart:14` (class IDs), `:106` (13 classes), `:112` (conf 0.25), `:116` (IoU 0.7), `:139` (decode) | - |
| Monument classifier | `monument_classifier.dart:94` (asset), `:129` (load), `:172` (classify) | `monument_classifier.tflite` |
| **Quaid-e-Azam portrait classifier** | `portrait_classifier.dart:77`, `:111`, `:154` | `portrait_classifier.tflite` |
| Rs 5,000 alteration CNN | `rs5000_anomaly_classifier.dart:21`, `:35` | `rs5000_mobilenetv3large.tflite` |
| Rs 5,000 genuine/counterfeit CNN | `pkr5000_counterfeit_classifier.dart:27`, `:43` | `mobilenetv3_pkr5000_counterfeit.tflite` |
| MobileNetV3-Small (switched off) | `mobilenetv3_small_classifier.dart`, switch `kSmallCnnEnabled` in `currency_rules.dart` | `mobilenetv3small_final.tflite` |
| Photo preparation (resize, letterbox 640) | `image_preprocessor.dart:128` (`prepare`), `:171` (`_letterbox`) | - |
| Reading serial / year text | `note_text_parser.dart:85`, `:191` | - |

How a model is "plugged in": `Interpreter.fromAsset('assets/models/<file>.tflite')` (package `tflite_flutter`) loads
it from the app's assets; the `pubspec.yaml` line `assets: - assets/models/` bundles the files into the APK.

## 3. "Where is the decision / the percentage calculated?"

File `features/verification/domain/verification_engine.dart`:

| What | Line |
|---|---|
| `evaluate()`: the main function that turns evidence into REAL / FAKE | 142 |
| Weighted score (earned / total weight) | 252 |
| Penalties and caps for failed checks | 287 |
| Choosing the verdict (any failure = FAKE) | 321-334 |
| `_passFactor`: confidence -> points (0.85 + 0.15 x ...) | 80 |
| `_check()`: how a check earns points | 443 |
| Denomination check | 479 |
| Serial numbers check / random-serial rule (`serialPatternName`) | 541 / 647 |
| SBP seals check | 710 |
| **Dots / lines check (exact count per note)** | 786 |
| Security thread check | 920 |
| Printed year check | 1002 |
| **Monument check** | 1377 |
| **Quaid-e-Azam portrait check** | 1475 |

Rules and weights: `features/verification/domain/currency_rules.dart` (what each note must show: `:58`; check weights:
`ScoreWeights` `:124`; penalty multipliers `:167`, `:174`; minimum confidences `:85`, `:113`, `:116`).
REAL needs a score of 85 or more: `features/verification/data/models/confidence_score_model.dart:53` (`bandFor`).

## 4. "Where is the data saved?"

| What | File : line |
|---|---|
| Save after every scan | `verification_controller.dart:125` (`saveScanQuietly`) |
| SQLite database + table `scans` | `features/history/data/scan_history_database.dart:20`, `:39` |
| One saved scan (fields) | `features/history/data/scan_record.dart` |
| CSV export | `features/history/domain/csv_export.dart:46`, `scan_history_database.dart:93` |

## 5. Training code (outside the app)

| What | File |
|---|---|
| Monument and portrait model training | `tools/train_monument.py` (`--kind portrait` for the portrait) |
| 10-fold cross-validation | `tools/train_monument.py --folds 10`, `tools/cv/` |
| YOLO11s training notebook | `New_Trained_Yolo-v11small.ipynb` (Colab) |
| MobileNetV3 notebooks | `MNV3small_model_on_6currency_pkr...ipynb`, `CNN_Model_5000pkr.ipynb` |

## 6. Handy answers

- **"Which file is the integration file?"** `on_device_currency_verification_repository.dart`. It loads every model,
  runs them on both photos and gathers the evidence; the rule engine then decides.
- **"Where is the 94-96% from?"** `confidence_gauge.dart:71` only *shows* it; it is calculated in
  `verification_engine.dart:252-313`.
- **"Does any model decide alone?"** No. Models give evidence; `verification_engine.dart` decides.
- **"Where is the monument / portrait?"** Models `monument_classifier.dart`, `portrait_classifier.dart`; checks
  `verification_engine.dart:1377` and `:1475`; shown in `security_features_card.dart`.
