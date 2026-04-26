# Counter-feit Currency Detection System
### Technical Documentation (Phase 1)

## 1. Introduction
This document details the architectural foundation, widget hierarchy, and core hardware communication modules currently implemented for the **Counter-feit Currency Detection System**. It serves as a structural reference outlining the frontend framework and application lifecycles established thus far.

## 2. Technology Stack
* **Framework:** Flutter SDK (Dart)
* **Design Guidelines:** Material 3 Spec
* **Core Hardware Packages:** `camera`, `image_picker`
* **Architecture Pattern:** Component-Driven Hierarchy (Separation of Views, Widgets, and Services)

## 3. Directory Structure and Modularity
The codebase strictly avoids monolithic anti-patterns in favor of highly decoupled components. This mitigates layout-thrashing, encourages reusability, and establishes a highly scalable foundation for upcoming deep-learning integrations.

* **`/lib/main.dart`**: Root entry point binding the native Flutter engine via `WidgetsFlutterBinding`.
* **`/lib/screens/`**: Stateful layout wrappers responsible for distinct user journeys and route handling.
* **`/lib/widgets/`**: Highly performant, reusable UI components decoupled from state layout layers.
* **`/lib/services/`**: Pure Dart configuration files mapping external hardware interfaces.

---

## 4. Key Application Modules

### 4.1 System Initialization & Pipeline
* **Splash Screen (`splash_screen.dart`):** Serves as an asynchronous aesthetic loading hub. Implements strict `FadeTransition` and `CurvedAnimation` properties using bounded `Tween` variables to provide a seamless boot-up experience.
* **Onboarding Interface (`onboarding_screen.dart`):** Educates the user regarding the application's capabilities utilizing a `PageView.builder`. Custom geometry mapping handles dynamic transition states.

### 4.2 Central System Routing
* **Main Navigation (`main_navigation.dart`):** Actuates the primary interface via a central floating scanning trigger. Heavily leverages an `IndexedStack` to ensure that standard route states (such as navigating back to the dashboard) are kept alive, neutralizing arbitrary UI rebuilding.

### 4.3 Hardware Interfacing (The Scanner Module)
The Scanner Module presents the heaviest technological architecture thus far, utilizing deep OS hardware ties and performance-restricted animation graphs.

* **Scan Tab (`scan_tab.dart`):** The master orchestrator for the native camera. Employs a `CameraController` wrapped meticulously within a `WidgetsBindingObserver`.
  * **Memory Deep Clean:** Any application backgrounding or pausing triggers an algorithmic hardware sweep, deliberately shutting down the camera `isolate` to prevent Android/iOS hardware-lock panics or graphical Black Screen artifacting upon returning to the app.
  * **`TickerMode` Tracking:** Automatically suspends background UI renders and live camera streams the nanosecond the application tab is visually occluded, securing enormous battery savings.
* **Scanner Overlay (`scanner_overlay.dart`):** Renders the user-facing hardware dimensions. Completely sidesteps notoriously expensive 'ParentDataWidget' layout bounds by rendering a `Transform.translate` algorithm inside a base `Stack`. This achieves a 60-FPS infinitely repeating laser graphic with nearly zero footprint on the UI thread.
* **Componentized Controls (`camera_controls_bar.dart`):** A strictly Stateless construct decoupling shutter bindings from screen matrices.
* **Image Picker Provider (`image_picker_service.dart`):** Extracted logic layer utilizing `XFile` methodologies to asynchronously fetch native filesystem objects.

---

## 5. Security & Hardware Stability Metrics
* Boot lifecycle is enforced via `WidgetsFlutterBinding.ensureInitialized()`, guaranteeing preemptive native-channel OS connections.
* Robust boundary restrictions ensure that `try/catch` pipelines surrounding the native platform calls execute safely, assuring the Dart isolate does not fatally panic on incompatible mobile lenses.

***
*Documentation Version: 1.0 (Phase 1)*
*Developer: Abdul Manan Kaleem*
