# Counterfeit Currency Detection System

A mobile app that checks whether a Pakistani Rupee (PKR) banknote is real or fake. You scan the note with your phone camera, and the app uses an AI model running directly on your device to give you a verdict — no internet needed.

Built with **Flutter** (Dart) for the mobile app, and **TensorFlow Lite** (MobileNetV3) for the AI model.

---

## What the App Does

1. **Scans your banknote** — Uses Google ML Kit's document scanner to automatically detect the note's edges, crop it, and fix the angle. Works like CamScanner.
2. **Asks for both sides** — Guides you to capture the front and back of the note in one session.
3. **Checks if it's actually a banknote** — Before running the AI, it uses image labeling to confirm you scanned a real piece of currency (not a random photo).
4. **Runs AI analysis on-device** — A MobileNetV3 model (~6.4 MB) classifies the note as Real or Fake. Everything runs locally on your phone.
5. **Averages both sides** — Combines the confidence scores from the front and back scans to reduce errors.
6. **Shows you the result** — Displays whether the note is authentic or counterfeit, a confidence percentage, and highlights where the Watermark and Security Thread should be.

---

## What's Been Built So Far

### Mobile App (Flutter)

| Screen | File | What it does |
|--------|------|-------------|
| Splash Screen | `splash_screen.dart` | Animated loading screen on app startup |
| Onboarding | `onboarding_screen.dart` | First-time user walkthrough (swipeable pages) |
| Dashboard | `dashboard_tab.dart` | Home screen with scan stats (how many real vs fake) and quick actions |
| Scanner | `scan_tab.dart` | Launches the ML Kit document scanner, handles front/back capture flow |
| Processing | `processing_screen.dart` | Shows a step-by-step progress animation while the AI analyzes both scans |
| Results | `result_screen.dart` | Shows the verdict, confidence %, and bounding boxes over the note image |
| History | `history_tab.dart` | List of previous scans |
| Navigation | `main_navigation.dart` | Bottom tab bar (Home, Scan, History) |

All screens use a **dark theme** with Material 3 design.

### AI / Machine Learning

| Component | Location | What it does |
|-----------|----------|-------------|
| Trained model | `model/currency_model.tflite` | MobileNetV3-Small, trained to classify PKR notes as real or fake |
| Model in app | `app/assets/models/currency_model.tflite` | Same model, bundled inside the Flutter app for on-device use |
| ML service | `app/lib/services/ml_service.dart` | Loads the model, runs inference, returns real/fake probabilities |
| Image preprocessing | `app/lib/services/image_preprocessing_service.dart` | Resizes images to 224×224, fixes rotation, boosts contrast and exposure |
| Training notebooks | `notebooks/Model Trained.ipynb` | Code used to train the model |
| Model comparison | `notebooks/Best models (5) accuracy.ipynb` | Compared 5 different model architectures for accuracy |
| TFLite converter | `scripts/convert_to_tflite.py` | Converts the trained Keras model to TFLite format |

### CI/CD

- **GitHub Actions** (`.github/workflows/build_apk.yml`) — Automatically builds a release APK whenever code is pushed to `main`.

### Documentation

- `docs/Project_Documentation.md` — Technical architecture details
- `docs/Supervisor_Meeting_Prep.md` — Viva/defense preparation Q&A
- `docs/Fake Currency Detection using MobileNetV3 Documentation.docx` — Formal project report

---

## How the Detection Pipeline Works

```
Phone Camera
    │
    ▼
ML Kit Document Scanner (auto edge detection, crop, perspective fix)
    │
    ▼
Front image captured → Back image captured
    │
    ▼
Sanity check: Is this actually a banknote? (ML Kit Image Labeler)
    │
    ▼
Image preprocessing (resize to 224×224, boost contrast, fix rotation)
    │
    ▼
TFLite model runs on each image → outputs [fake %, real %]
    │
    ▼
Average the front and back probabilities together
    │
    ▼
Show result: Real or Fake, confidence %, security feature overlay
```

---

## Project Structure

```
FYP-Fake-Currency-Detection/
│
├── app/                        ← Flutter mobile app
│   ├── lib/
│   │   ├── main.dart           ← App entry point
│   │   ├── screens/            ← All UI screens (listed in table above)
│   │   ├── services/           ← ML inference, image processing, image picker
│   │   └── models/             ← Data models (scan_model.dart)
│   ├── assets/models/          ← Bundled TFLite model
│   ├── pubspec.yaml            ← Flutter dependencies
│   └── android/ & ios/         ← Platform-specific configs
│
├── model/                      ← Exported ML model (currency_model.tflite)
├── notebooks/                  ← Jupyter notebooks for training & evaluation
├── scripts/                    ← Utility scripts (Keras → TFLite converter)
├── Data-Set/                   ← Links to training dataset
├── docs/                       ← Project documentation & defense prep
└── .github/workflows/          ← CI/CD pipeline (auto-build APK)
```

---

## How to Run It

**You need:** Flutter SDK installed ([install guide](https://docs.flutter.dev/get-started/install))

```bash
# 1. Clone the repo
git clone https://github.com/Abdul-Manan-Kaleem/FYP-Fake-Currency-Detection.git

# 2. Go into the app folder
cd FYP-Fake-Currency-Detection/app

# 3. Install dependencies
flutter pub get

# 4. Connect a physical Android device and run
flutter run
```

> **Note:** The scanner needs camera access. Make sure your device has camera permissions enabled.

**For retraining the model (optional):** You need Python 3.10+ and the packages listed in the notebooks.

---

## Team

| Role | Name |
|------|------|
| Supervisor | M. Junaid Khan |
| Developer | Abdul Manan Kaleem |
| Model Training | Raja Waleed |
| Testing & Documentation | M. Usman |

*Final Year Project — Department of Computer Science*
