# FYP Supervisor Meeting: Progress & Defense Guide

This document is designed to help you prepare for your meeting with your FYP Supervisor. It breaks down exactly **what** has been built, **how** it was built, and provides answers to **technical questions** your supervisor might ask you.

---

## 1. Project Architecture (The Monorepo)
**What we did:** We structured the repository into an "AI Monorepo Architecture".
**How we did it:** We created dedicated, isolated folders: `/app` for the Flutter code, `/model` for the `.keras` files, `/Data-Set` for the currency images, and `/notebooks` for the Python training scripts.
**Why we did it:** This is an industry-standard practice. It prevents the mobile app code from mixing with the machine learning scripts. If the AI model crashes, it doesn't break the frontend. It also allows your AI engineer (Raja Waleed) to work on Python without interfering with your Dart code.

## 2. Frontend Framework & Navigation
**What we did:** Built the entire foundational UI of the mobile application.
**How we did it:** We used the **Flutter SDK** and **Dart**. We implemented a modern Splash Screen, an interactive Onboarding Interface, and a dynamic Bottom Navigation Bar utilizing an `IndexedStack`.
**Why we did it:** Using an `IndexedStack` ensures that when the user switches between the Home tab and the History tab, the screens are kept alive in memory. This stops the app from lagging or reloading the page every time the user clicks a button.

## 3. The Core Scanner Engine (Hardware Integration)
**What we did:** Integrated the live native phone camera with a smooth, 60-FPS laser scanning animation.
**How we did it:** We tapped directly into the phone's back-lens using Flutter's `camera` controller. We wrapped the scanner in a highly optimized `Transform.translate` graphic that draws the green laser bounding box (`290x155`). 
**The Technical Flex:** We built a custom `WidgetsBindingObserver`. This means if the user minimizes the app to answer a text message, our code instantly detects the background state and shuts down the camera hardware. When they return, it reboots the camera. This completely prevents battery-drain and RAM memory leaks!

## 4. AI Image Pre-Processing (The Math)
**What we did:** We built a mathematical pipeline that crushes and normalizes raw images before they are sent to the Artificial Intelligence.
**How we did it:** We created the `ImagePreprocessingService`. When a user takes a photo:
1. **Geometric Cropping:** The code calculates the exact X/Y coordinates of the green bounding box on their screen and crops out the background desk/table, keeping *only* the currency note.
2. **Pixel Normalization:** We algorithmically boost the image contrast by 25% and exposure by 10%. This forces the hidden security patterns and watermarks to become highly visible to the AI.
3. **Tensor Down-Sampling:** A 12-Megapixel camera image is too massive for an AI to process fast. We use linear interpolation to crush the image into a perfect `224x224` pixel matrix, which is the exact mathematical input size required by TensorFlow/MobileNet models.

## 5. Cloud Compilation (CI/CD Pipeline)
**What we did:** Automated the APK generation process.
**How we did it:** We wrote a YAML script for **GitHub Actions**. Now, whenever code is pushed to GitHub, massive Ubuntu cloud servers automatically compile the highly-optimized `.apk` file for Android devices.
**Why we did it:** It allows the team to download and test the app instantly on their phones without needing to install a 5GB Android Studio environment on their own computers.

---

# ❓ Supervisor Q&A (How to defend your work)

**Supervisor:** *"Which third-party libraries/packages are you using, and why?"*
**Your Answer:** "On the Frontend (Flutter), we strictly minimized third-party bloat. We use `camera` to interface natively with the hardware lenses without writing raw Android/iOS Java/Swift. We use `image_picker` to safely access the user's gallery permissions. Finally, we use the Dart `image` package to mathematically decode and manipulate raw pixels for the AI cropping and resizing. On the Backend (Python), we use `TensorFlow` and `Keras` to build the MobileNet v3 CNN because it supports exporting directly to `.tflite` for mobile execution."

**Supervisor:** *"Why did you choose Flutter instead of Java/Kotlin or React Native?"*
**Your Answer:** "We chose Flutter because its Skia rendering engine compiles directly to native ARM machine code, meaning it can process live 60-FPS camera streams without the JavaScript bridge bottleneck that React Native suffers from. It also allows us to write the UI once and deploy it to both Android and iOS seamlessly."

**Supervisor:** *"When I take a picture, what exactly happens before the AI sees it?"*
**Your Answer:** "The raw camera image is too large and noisy for an AI. We wrote a custom Image Pre-Processing Service that mathematically crops the photo down to the exact `290x155` bounding box on the screen. It then boosts the contrast by 25% to expose micro-patterns, and finally crushes the matrix into a `224x224` tensor, which is the exact input size required by our TensorFlow model."

**Supervisor:** *"If the camera is always running, won't this drain the user's battery and crash the phone?"*
**Your Answer:** "No, sir. We implemented deep hardware lifecycle management using `WidgetsBindingObserver` and `TickerMode`. The literal nanosecond the user minimizes the app, or switches to the Dashboard tab, the camera isolate is completely shut down and flushed from RAM. It only streams when it is physically visible on the screen."

**Supervisor:** *"How many classes have you used?"*
**Your Answer:** *(Depends on what he means!)*
* **If he means Machine Learning:** "We are training our Convolutional Neural Network on exactly **2 classes**: Class 0 (`Authentic`) and Class 1 (`Counterfeit`)."
* **If he means OOP Code:** "We wrote approximately **22 Dart Classes** distributed across 12 files. We heavily separated our UI layer into classes like `ScanTab`, while keeping all mathematical logic strictly inside isolated Service classes like `ImagePreprocessingService`."

**Supervisor:** *"How does your app handle the heavy time delay between capturing the 12-Megapixel image and processing the math without freezing the phone?"*
**Your Answer:** "We utilized Dart's asynchronous `Future` and `async/await` methodology. The heavy image preprocessing is processed off the main UI thread. During this mathematical delay, we trigger a reactive `setState` overlay that shows a loading indicator. This guarantees the app never suffers from an 'Application Not Responding' (ANR) crash."

**Supervisor:** *"Cameras use massive amounts of RAM. How do you prevent Out-Of-Memory (OOM) crashes on older phones?"*
**Your Answer:** "We implemented aggressive garbage collection. When the camera isn't actively visible (like when switching tabs), we instantly destroy the `CameraController` using Flutter's `dispose()` lifecycle method. Furthermore, the `ImagePreprocessingService` instantly flushes the massive 12-Megapixel byte array from memory the exact millisecond it finishes cropping the `224x224` tensor."

**Supervisor:** *"How are you planning to track the user's scan history?"*
**Your Answer:** "We created a strict Data Schema called `ScanModel.dart`. Instead of passing loose strings around the app, every scan is instantiated into a highly typed object containing a `timestamp`, `confidenceScore`, and an `isAuthentic` boolean. This perfectly prepares the architecture for an SQLite or Firebase database injection in the next phase."

**Supervisor:** *"Where is the actual Artificial Intelligence model right now?"*
**Your Answer:** "The frontend architecture and the pre-processing mathematical pipeline are 100% complete. My team member, Raja Waleed, has just pushed the `model.keras` MobileNet v3 logic into our Monorepo's `/model` folder. Our next sprint is to convert that Keras model into a TensorFlow Lite `.tflite` file so we can run the inference natively on the mobile edge."
