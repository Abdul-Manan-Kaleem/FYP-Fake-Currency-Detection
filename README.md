# Counterfeit Currency Detection System

An On-Device Artificial Intelligence Solution for Pakistani Banknote Authentication

---

## Project Overview

The **Counterfeit Currency Detection System** is an advanced mobile solution designed to verify the authenticity of Pakistani Rupee (PKR) banknotes in real time. Powered by on-device deep learning, the system allows users to capture photos of a banknote using their smartphone camera and immediately receive an accurate verification verdict without requiring an active internet connection.

The application combines **Flutter** for a responsive cross-platform mobile interface and an optimized **MobileNetV3-Small TensorFlow Lite model** for low-latency, private, on-device artificial intelligence inference.

---

## Core Application Workflow

1. **Intelligent Document Scanning**: Utilizes Google ML Kit Document Scanner to automatically detect banknote boundaries, crop excess background, and correct perspective angles.
2. **Dual-Sided Verification**: Guides the user through capturing both the front and back of the banknote for comprehensive analysis.
3. **Currency Validation Pre-Check**: Verifies that the scanned image is indeed a banknote before running deep learning analysis, preventing false inputs.
4. **On-Device AI Classification**: Processes the scanned images locally through an optimized 6.4 MB MobileNetV3 neural network to calculate real versus counterfeit probability scores.
5. **Score Aggregation**: Combines and averages confidence metrics from both banknote sides to eliminate single-perspective false positives.
6. **Visual Result Reporting**: Displays the overall authentication verdict, confidence percentage, and an interactive overlay mapping key security features such as the Watermark and Security Thread.

---

## System Components

### Mobile Application Features
- **Splash & Onboarding**: Smooth welcome animations and intuitive first-time user guidance.
- **Interactive Dashboard**: Overview of past scan analytics, quick scan triggers, and security tips.
- **Smart Scanner**: Real-time camera viewfinder with automatic document cropping.
- **Step-by-Step Processing**: Visual feedback while AI models analyze image layers.
- **Detailed Results**: Clear verdict display with confidence metrics and feature overlay maps.
- **Scan History**: Historical log of past currency verifications saved locally on the device.

### Artificial Intelligence & Machine Learning
- **MobileNetV3 Neural Network**: Compact deep learning architecture optimized for mobile devices.
- **TensorFlow Lite Engine**: High-performance local inference engine bundled directly inside the application package.
- **Image Preprocessing Pipeline**: Automated image normalization, 224x224 scaling, contrast adjustment, and rotation correction.

### Continuous Integration & Deployment
- **Automated Builds**: Integrated GitHub Actions workflow that compiles release Android application packages (APK) automatically on project updates.

---

## Application Architecture

- **Mobile Application**: Located in the `app` folder, containing all user interface screens, services, and native Android/iOS platform configurations.
- **Machine Learning Models**: Located in the `model` folder, containing trained model weights and TensorFlow Lite exports.
- **Research & Development**: Located in the `notebooks` folder, containing model training experiments and accuracy evaluations.
- **Project Documentation**: Located in the `docs` folder, containing comprehensive technical architecture reports and presentation materials.

---

## Running the Application

To run the application on a physical smartphone or emulator:

1. Ensure the Flutter SDK is installed on your development system.
2. Open a terminal in the application directory (`app`).
3. Fetch application dependencies using `flutter pub get`.
4. Connect an Android smartphone with camera permissions enabled and run `flutter run`.

---

## Project Team

- **Supervisor**: M. Junaid Khan  
- **Lead Developer**: Abdul Manan Kaleem  
- **Machine Learning Specialist**: Raja Waleed  
- **Quality Assurance & Documentation**: M. Usman  

*Final Year Project — Department of Computer Science*
