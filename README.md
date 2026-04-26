# Counter-feit Currency Detection System (FYP)

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)
![Android](https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-000000?style=for-the-badge&logo=ios&logoColor=white)

A robust, enterprise-grade AI-powered currency detection mobile application. Built natively with Flutter specifically to authenticate and detect counterfeit Pakistani Rupee (PKR) notes using high-resolution scanning, UV mapping, and AI-driven security validations.

---

## Application Architecture & Features

The Counter-feit Currency Detection System is architected leveraging professional software engineering practices, separating UI layers from hardware logic to ensure a bug-free, performant experience.

* **Advanced Scanning Module (`lib/widgets`, `lib/screens/scan_tab.dart`):**
  * **Live Engine Initialization**: Deeply integrated Flutter `camera` controller initializing back-mounted hardware with a fluid `290x155` dynamic alignment viewfinder.
  * **Optimized Event Lifecycles**: Custom built-in `WidgetsBindingObserver` that intelligently garbage-collects and releases the camera pipeline instantly when the application is backgrounded, mitigating hardware locking and memory leaks.
  * **Background Battery Protection**: Utilizes `TickerMode` to pause active streaming the moment the user navigates away from the scanner tab.
  * **Modular Hardware Services**: Abstracted `ImagePickerService` decoupling gallery reading configurations from UI state logic.
  
* **Interactive UI/UX Infrastructure:**
  * **Modern Frameworks:** Prioritizing modern Material 3 design specifications utilizing precise hexadecimal tokens (`0xFF0B0F19`, `0xFF00D2FF`) for dark mode interfaces.
  * **Orchestration & Routing**: Optimized transient states navigating from system initialization, to onboarding pipelines, to a stabilized core navigation architecture.
  * **Dynamic Dashboard Analytics**: Real-time analytical tracking mapping Authentic versus Fake hit ratios.
  * **Log Tracking**: Historical localized `ListView` modeling mock previous scans.

## Code Structure

This repository utilizes a professional **monorepo architecture** tailored for Machine Learning and Mobile App development. By segregating the AI pipeline from the mobile frontend, the project scales effortlessly and isolates development environments.

```text
FYP-Fake-Currency-Detection/
├── app/                       # Flutter Mobile Application
│   ├── lib/                   # Core Dart codebase (Screens, Widgets, Services)
│   ├── pubspec.yaml           # Flutter dependencies
│   └── android/ & ios/        # Native hardware bindings
├── Data-Set/                  # Machine Learning Data
│   ├── fake_currency/         # Scraped or generated counterfeit samples
│   └── real_currency/         # High-resolution authentic samples
├── model/                     # Exported ML Models
│   ├── v1_model.tflite        # TensorFlow Lite models for on-device inference
│   └── checkpoints/           # Model weight backups
├── notebooks/                 # AI Training & Experiments
│   ├── data_preprocessing.ipynb # Dataset augmentation notebooks
│   └── cnn_training.ipynb     # Deep learning model training logic
├── scripts/                   # Python Utility Scripts
│   └── mass_resize.py         # Batch image normalizers
└── docs/                      # Technical Documentation
    └── Project_Documentation.md # Detailed architecture outlines
```

## Getting Started

To compile and execute a local copy of this software architecture, proceed with the following steps.

### Prerequisites
**For Mobile App Development:**
* [Flutter SDK](https://docs.flutter.dev/get-started/install) (Required to compile and run the mobile application).

**For AI Model Training (Optional):**
* Python 3.10+ (Only required if you are retraining the machine learning models inside the `/notebooks` or `/scripts` directories).

### Installation
1. **Clone the repository:**
   ```bash
   git clone https://github.com/Abdul-Manan-Kaleem/FYP-Fake-Currency-Detection.git
   ```
2. **Navigate to the core Flutter project:**
   ```bash
   cd FYP-Fake-Currency-Detection/app
   ```
3. **Pull Package Dependencies:**
   ```bash
   flutter pub get
   ```
4. **Deploy Application to Target Environment:**
   ```bash
   flutter run
   ```
*(Note: Ensure your physical deployment device has Camera Permissions injected into AndroidManifest.xml or Info.plist if triggering hardware features).*

## Development Roadmap (AI Integrations)
- [x] Initializing Core Scaffold and Tab Navigation
- [x] Abstracting Platform Camera Streams & Deep UI Overlays
- [x] Architectural Lifecycle Refactoring
- [ ] Deep Learning Edge Integration (On-Device TensorFlow Lite model)
- [ ] Instantaneous PKR Mapping & Matrix Veracity Plotting

---
**Developer: ** Abdul Manan Kaleem
**Model Training: ** Raja Waleed
**Tester & Docementation: ** M. Usman
*Final Year Project (FYP-1)*  
*Department of Computer Science *
