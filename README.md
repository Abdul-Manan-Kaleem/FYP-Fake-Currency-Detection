# Counterfeit Currency Detection System

> **An On-Device Artificial Intelligence Solution for Pakistani Banknote Authentication**

[![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen?style=for-the-badge&logo=githubactions)](https://github.com/Abdul-Manan-Kaleem/FYP-Fake-Currency-Detection/actions)
[![Framework](https://img.shields.io/badge/Framework-Flutter%203.x-02569B?style=for-the-badge&logo=flutter)](https://flutter.dev)
[![AI Engine](https://img.shields.io/badge/AI%20Engine-TensorFlow%20Lite-FF6F00?style=for-the-badge&logo=tensorflow)](https://www.tensorflow.org/lite)
[![Architecture](https://img.shields.io/badge/Model-MobileNetV3--Small-412991?style=for-the-badge)](https://arxiv.org/abs/1905.02244)
[![Target Currency](https://img.shields.io/badge/Target-Pakistani%20Rupee%20(PKR)-006600?style=for-the-badge)](https://www.sbp.org.pk)

---

## Executive Summary

Counterfeit banknotes pose a significant economic threat to financial stability, business operations, and consumer trust—particularly in cash-dominant economies like Pakistan. Traditional verification methods rely on specialized ultraviolet (UV) lamps, magnetic sensors, or manual inspection by trained personnel, which are inaccessible to the general public.

The **Counterfeit Currency Detection System** addresses this challenge by delivering an accessible, high-precision artificial intelligence authentication tool directly to smartphones. Utilizing an optimized **MobileNetV3-Small Convolutional Neural Network (CNN)** running locally via **TensorFlow Lite**, the application analyzes physical security features of Pakistani Rupee (PKR) banknotes (such as watermarks, micro-lettering, and security threads) in real time with **98.4% classification accuracy**—requiring zero cloud connectivity or external server infrastructure.

---

## Table of Contents

- [Executive Summary](#executive-summary)
- [Key Features & Innovations](#key-features--innovations)
- [End-to-End System Architecture](#end-to-end-system-architecture)
- [Artificial Intelligence & Model Methodology](#artificial-intelligence--model-methodology)
- [Machine Learning Performance & Benchmarks](#machine-learning-performance--benchmarks)
- [Application Structure & Module Map](#application-structure--module-map)
- [User Experience & Screen Workflows](#user-experience--screen-workflows)
- [Installation & Developer Setup Guide](#installation--developer-setup-guide)
- [CI/CD & Cloud Compilation](#cicd--cloud-compilation)
- [Hardware Lifecycle & Security Guard](#hardware-lifecycle--security-guard)
- [Academic Project Metadata](#academic-project-metadata)

---

## Key Features & Innovations

### 1. 100% On-Device & Privacy-Preserving AI
Inference executes entirely on the user's mobile device via TensorFlow Lite. Banknote scans never leave the smartphone, guaranteeing complete user privacy, zero data consumption, and instant offline availability in remote regions.

### 2. Intelligent Document Scanning (CamScanner-Style UX)
Integrated with **Google ML Kit Document Scanner**, the system automatically detects currency note edges in real time, crops out background noise (tables, hands, counters), and applies perspective unwarping to produce flat rectangular images for AI evaluation.

### 3. Banknote Pre-Validation Sanity Check
Before triggering deep learning inference, the application utilizes Google ML Kit Image Labeling to verify that the captured frame actually contains currency notes, preventing false execution on arbitrary non-banknote objects.

### 4. Dual-Sided Scan Ensembling
Recognizing that front and back note faces present distinct security features, the application guides users through a dual-sided capture sequence. Real/fake probabilities from both scans are mathematically averaged to eliminate single-perspective false positives.

### 5. Interactive Security Feature Mapping
Upon completing classification, the app renders localized bounding boxes directly over the captured image, visually highlighting critical verification zones including the **Watermark** and **Security Thread**.

---

## End-to-End System Architecture

```
                                  USER INTERFACE
                                 [ Phone Camera ]
                                        │
                                        ▼
                          [ ML Kit Document Scanner ]
                       (Auto Edge Detection & Crop)
                                        │
                                        ▼
                           Dual-Sided Image Capture
                        ┌───────────────┴───────────────┐
                        ▼                               ▼
                 [ Front Image ]                 [ Back Image ]
                        │                               │
                        └───────────────┬───────────────┘
                                        │
                                        ▼
                         [ Banknote Validation Check ]
                         (ML Kit Image Labeler Sanity)
                                        │
                                        ▼
                        [ Image Preprocessing Service ]
               - EXIF Orientation & Matrix Crop (290x155)
               - Contrast Boost (+25%) & Exposure (+10%)
               - Tensor Down-Sampling to 224x224 Matrix
                                        │
                                        ▼
                        [ On-Device TensorFlow Lite ]
                     (MobileNetV3-Small Neural Network)
                                        │
                                        ▼
                       [ Dual-Probability Ensembling ]
               P_final = (P_front_real + P_back_real) / 2
                                        │
                                        ▼
                          [ Analysis Verdict Screen ]
             - Authentic / Counterfeit Classification Status
             - Aggregated Confidence Score Percentage
             - Bounding Box Overlay for Watermark & Thread
```

---

## Artificial Intelligence & Model Methodology

### 1. Model Architecture
The core classification model utilizes **MobileNetV3-Small**, a lightweight deep neural network designed using Hardware-Aware Network Architecture Search (NAS) and NetAdapt algorithms, optimized for mobile CPU/GPU execution.

- **Input Dimension**: `224 × 224 × 3` RGB Tensor
- **Feature Extraction**: Hard-Swish activation functions, depthwise separable convolutions, and Squeeze-and-Excitation (SE) attention blocks.
- **Model Footprint**: `6.4 MB` quantized `.tflite` asset bundled inside the application package.
- **Inference Speed**: `~45 milliseconds` per frame on modern smartphones.

### 2. Mathematical Preprocessing Pipeline
Raw hardware camera frames require mathematical normalization prior to neural network ingestion:

1. **Bounding Box Isolation**: Calculates hardware-to-screen pixel ratios to isolate the `290 × 155` alignment frame.
2. **Contrast & Exposure Boosting**: Algorithmically enhances contrast by **+25%** and exposure by **+10%** to highlight faint watermarks and micro-lettering.
3. **Tensor Down-Sampling**: Employs bilinear interpolation to scale images down to the `224 × 224` matrix required by TensorFlow models.

---

## Machine Learning Performance & Benchmarks

During model development, five candidate deep learning architectures were trained and evaluated on the dataset to select the optimal model for mobile deployment:

| Architecture | Accuracy | Precision | Recall | F1-Score | Inference Time | Model Size | Status |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **MobileNetV3-Small** | **98.4%** | **98.6%** | **98.2%** | **98.4%** | **~45 ms** | **6.4 MB** | **Selected (Production)** |
| MobileNetV2 | 96.8% | 97.1% | 96.5% | 96.8% | ~68 ms | 14.2 MB | Evaluated |
| EfficientNet-B0 | 97.5% | 97.8% | 97.2% | 97.5% | ~110 ms | 20.5 MB | Evaluated |
| ResNet-50 | 98.1% | 98.3% | 97.9% | 98.1% | ~240 ms | 98.0 MB | Evaluated (Too Heavy) |
| Custom 4-Layer CNN | 89.2% | 88.5% | 89.8% | 89.1% | ~35 ms | 4.1 MB | Evaluated (Underfitted) |

*MobileNetV3-Small was selected for production due to its ideal balance of near-peak accuracy (98.4%), fast inference latency (~45 ms), and compact memory footprint (6.4 MB).*

---

## Application Structure & Module Map

```
FYP-Fake-Currency-Detection/
│
├── app/                                    ← Primary Flutter Mobile Application
│   ├── assets/
│   │   └── models/
│   │       └── currency_model.tflite       ← Bundled TensorFlow Lite Neural Network
│   ├── android/                            ← Native Android Platform Configurations (minSdk 21)
│   ├── ios/                                ← Native iOS Platform Configurations
│   ├── lib/
│   │   ├── main.dart                       ← Application Entry Point & Global Configuration
│   │   ├── models/
│   │   │   └── scan_model.dart             ← Typed Data Schema for Scan Records
│   │   ├── services/
│   │   │   ├── ml_service.dart             ← TFLite Inference Engine & ML Kit Integration
│   │   │   ├── image_preprocessing_service.dart ← Tensor Resizing, Normalization & Cropping Math
│   │   │   └── image_picker_service.dart   ← Native File System & Gallery Picker Utility
│   │   └── screens/
│   │       ├── splash_screen.dart          ← Boot Animation & Native Engine Binding
│   │       ├── onboarding_screen.dart      ← First-Time User Interactive Walkthrough
│   │       ├── main_navigation.dart        ← Tab Host utilizing Memory-Preserving IndexedStack
│   │       ├── dashboard_tab.dart          ← Analytics Dashboard & Quick Scan Triggers
│   │       ├── scan_tab.dart               ← Hardware Camera Controller & Live Scanner
│   │       ├── processing_screen.dart      ← Step-by-Step AI Verification Progress View
│   │       ├── result_screen.dart          ← Verdict View with Confidence & Feature Overlays
│   │       └── history_tab.dart            ← Historical Scan Records Log
│   └── pubspec.yaml                        ← Dependency Manifest & Asset Declarations
│
├── model/                                  ← Exported Keras & TFLite Model Files
├── notebooks/                              ← Jupyter Notebooks for Training & Model Selection
├── scripts/                                ← Python Utilities (Keras to TFLite Converter)
├── Data-Set/                               ← Dataset Storage Links & Verification Manifests
├── docs/                                   ← Technical Documentation & Presentation Material
└── .github/workflows/
    └── build_apk.yml                       ← CI/CD Cloud Pipeline for Release APK Compilation
```

---

## User Experience & Screen Workflows

1. **Splash Screen**: Establishes asynchronous channel connections to native mobile operating system features before loading UI routes.
2. **Onboarding Flow**: Introduces users to proper scanning practices (flat placement, adequate lighting, scanning both note faces).
3. **Dashboard**: Presents historical verification statistics (total scans, real count, fake count) and instant scan launch buttons.
4. **Smart Scanner**: Launches the live hardware camera with auto-focus, crop guides, flash toggles, and document perspective corrections.
5. **AI Processing Center**: Animates the multi-step verification process (Image capture → Watermark pattern analysis → Microprint verification → Security thread check → Final scoring).
6. **Results & Overlay Screen**: Highlights the verdict in high-contrast green (Authentic) or red (Counterfeit), displays exact confidence percentages, and projects security feature boxes over the image.

---

## Installation & Developer Setup Guide

### System Prerequisites
- **Flutter SDK**: `Version 3.2.0 or higher` ([Install Instructions](https://docs.flutter.dev/get-started/install))
- **Dart SDK**: `Version 3.2.0 to <4.0.0`
- **Android Studio / Xcode**: Configured for Android (`minSdkVersion 21`) or iOS testing.

### Quick Start Setup
```bash
# 1. Clone the repository
git clone https://github.com/Abdul-Manan-Kaleem/FYP-Fake-Currency-Detection.git

# 2. Navigate to the core Flutter application directory
cd FYP-Fake-Currency-Detection/app

# 3. Retrieve package dependencies
flutter pub get

# 4. Connect a physical Android or iOS device and run the application
flutter run
```

---

## CI/CD & Cloud Compilation

The repository includes an automated **GitHub Actions** continuous integration pipeline configured in `.github/workflows/build_apk.yml`. 

Whenever code updates are committed to the `main` branch, cloud build runners execute:
1. Java JDK 17 & Flutter SDK environment initialization.
2. Dependency installation (`flutter pub get`).
3. Automated release APK compilation (`flutter build apk --release`).
4. Artifact deployment, making downloadable `.apk` binaries immediately accessible under GitHub repository actions.

---

## Hardware Lifecycle & Security Guard

To ensure high performance and prevent battery drain or memory leaks during active camera usage:

- **Lifecycle Sweep**: Implements `WidgetsBindingObserver` to monitor mobile operating system app lifecycle states. If the user backgrounded or minimized the app, camera isolates are immediately closed and RAM is flushed.
- **Resource Suppression**: Employs `TickerMode` to pause offscreen animation graphs during navigation transitions, preventing UI thread stutter.
- **Memory Safety**: Immediately disposes raw 12-Megapixel byte streams post-cropping, restricting active memory usage to `<40 MB RAM`.

---

## Academic Project Metadata

- **Project Title**: Counterfeit Currency Detection System
- **Academic Program**: Final Year Project (FYP-2)
- **Department**: Department of Computer Science
- **Academic Term**: 2025 – 2026

### Project Team & Roles
| Name | Project Role | Primary Focus |
| :--- | :--- | :--- |
| **M. Junaid Khan** | Project Supervisor | Academic Oversight & Architectural Guidance |
| **Abdul Manan Kaleem** | Lead Developer | Mobile Application Engineering, Hardware Integration & Preprocessing |
| **Raja Waleed** | Machine Learning Specialist | Neural Network Training, Optimization & TFLite Conversion |
| **M. Usman** | QA & Documentation Lead | System Testing, Dataset Verification & Technical Documentation |

---

*Developed at the Department of Computer Science — Building accessible, privacy-preserving AI tools for financial security.*
