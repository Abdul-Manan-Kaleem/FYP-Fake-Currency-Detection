# Fake Currency Detector: Pakistani Banknote Verification (FYP-2)

> **On-device verification of Pakistani Rupee (PKR) notes:** YOLO11s security-feature detection,
> OCR serial matching, a back-side monument classifier and Rs 5,000 counterfeit CNNs, all
> running offline on an Android phone.

[![Framework](https://img.shields.io/badge/Flutter-3.47-02569B?style=for-the-badge&logo=flutter)](https://flutter.dev)
[![AI Engine](https://img.shields.io/badge/TensorFlow%20Lite-on--device-FF6F00?style=for-the-badge&logo=tensorflow)](https://www.tensorflow.org/lite)
[![Detector](https://img.shields.io/badge/YOLO11s-13%20classes-412991?style=for-the-badge)](https://docs.ultralytics.com)
[![Currency](https://img.shields.io/badge/Target-PKR%2010%20→%205000-006600?style=for-the-badge)](https://www.sbp.org.pk)

The current application is **[`fake_currency_detector/`](fake_currency_detector/)**.
The older prototype in [`app/`](app/) is kept for reference (see [Repository layout](#repository-layout)).

---

## Contents

- [What the app does](#what-the-app-does)
- [How a scan works](#how-a-scan-works)
- [Models](#models)
- [Verification rules](#verification-rules)
- [Results and verdicts](#results-and-verdicts)
- [Datasets and training](#datasets-and-training)
- [Repository layout](#repository-layout)
- [Build and run](#build-and-run)
- [Tests](#tests)
- [Known limitations](#known-limitations)
- [Academic project metadata](#academic-project-metadata)

---

## What the app does

The user scans the **front** (Quaid-e-Azam side) and the **back** (monument side) of a
Pakistani banknote. The phone checks the note's physical security features, reads and compares its
serial numbers, recognises the monument on the back and, for Rs 5,000, runs two counterfeit
classifiers. It then gives a verdict with an explanation for every check.

| Supported notes | Rs 10 · 20 · 50 · 100 · 500 · 1000 · 5000 |
|---|---|
| Runs | Fully **on device**, offline: no server, no account, no data leaves the phone |
| Platform | Android (ML Kit document scanner needs Google Play services). iOS falls back to camera + manual crop |
| Languages | English UI with Roman-Urdu messages for users ("Jaali Note", "Ye note ki back side hai!"…) |

**Features**

- **Guided two-sided capture** with Google ML Kit's document scanner: auto edge detection,
  auto capture, perspective correction and background removal. A gallery upload with a free crop
  (zoom in and out freely) is also available.
- **Front/back check right after each scan:** a back scanned at the front step, the same side
  twice, or the back of a different note ("Ye 5000 ka note hai, aap 1000 scan kar rahe hain") is
  caught with a vibration and a pop-up, and the photo is not kept.
- **Not-a-note, half-note and photocopy detection** before any analysis.
- **Security features found by YOLO11s:** denomination (both sides), SBP seals (1 front, 3 back),
  security thread, denomination lines/dots, both serial-number regions and the printed year.
- **OCR inside YOLO's boxes:** both serials read twice and compared character by character; the
  printed year is read too.
- **Back-side monument verification** (Bab-e-Khyber … Faisal Mosque) by a MobileNetV2 classifier
  trained on the project dataset.
- **Rs 5,000 extras:** a synthetic-alteration CNN, a genuine/counterfeit CNN, and an edge-microprint
  check ("5000" repeated along the border) with a guided close-up camera (zoom slider, tap to
  focus, auto torch below 50 lux, Urdu blur hint).
- **Diagnostic report:** score gauge, verdict, a pass/fail/unclear row for each feature, the
  character-level serial comparison, YOLO boxes drawn on both photos ("What YOLO11s saw"), and
  per-stage timings.

---

## How a scan works

```
 FRONT capture ──┐                                     ┌── BACK capture
 (ML Kit scanner │  per side, right after capture:     │  or gallery + free crop)
  or gallery)    ▼                                     ▼
         ┌────────────────────────────────────────────────────┐
         │ native decode → 2,048 px working copy (in memory)  │
         │ YOLO11s (640 letterbox) · monument CNN (224)       │
         │ front/back + denomination check → pop-up if wrong  │
         └────────────────────────────────────────────────────┘
                                 │  "ANALYZE" reuses these scans
                                 ▼
  1. Photocopy / printer paper on a note?  ──────────────► JAALI NOTE / FAKE
  2. Half or cut-off note (shape ≠ that note's shape)? ──► INCOMPLETE NOTE IMAGE
  3. A real note? (note class + security features)  ────► INVALID OBJECT
  4. Image quality (blur, glare, brightness)        ────► UNABLE TO VERIFY
  5. OCR inside YOLO boxes: serials ×2 passes, printed year
  6. Rs 5,000 only: full-resolution edge microprint OCR, alteration CNN, counterfeit CNN
  7. Back-side monument
                                 ▼
           VerificationEngine (rules below) → verdict + score + report
```

Architecture: feature-first clean architecture (`core/`, `features/scanner/`,
`features/verification/{data,domain,presentation}`), Riverpod state, everything in memory.

---

## Models

All models run with TensorFlow Lite on the phone. They live in
`fake_currency_detector/assets/models/` and are committed to this repository.

| Model | File | Size | Role | Never used for |
|---|---|---|---|---|
| **YOLO11s** (Ultralytics, 13 classes) | `yolo11s_currency.tflite` | 38.0 MB | Note presence, denomination of each side, SBP seals, thread, lines, dots, serial regions, printed year | Reading text, deciding fake on its own |
| **ML Kit text recognition** | (Google Play / bundled) | n/a | Reads the text **inside** YOLO's serial and year boxes, and the Rs 5,000 border microprint | Finding features |
| **Monument classifier** (MobileNetV2) | `monument_classifier.tflite` | 8.9 MB | Which monument the back shows (7 monuments + `invalid`) | Front side |
| **Rs 5,000 alteration CNN** (MobileNetV3-Large) | `rs5000_mobilenetv3large.tflite` | 3.4 MB | Synthetic-alteration probability, Rs 5,000 only | Other notes |
| **Rs 5,000 genuine/counterfeit CNN** (MobileNetV3-Large, from `.pth`) | `mobilenetv3_pkr5000_counterfeit.tflite` | 16.8 MB | P(counterfeit), Rs 5,000 only | Other notes |

**YOLO11s contract** (read from the model, checklist items 11–19 in the app README):
input `float32[1,3,640,640]` **channels-first**, RGB 0–1, letterboxed with grey 114. Output
`float32[1,17,8400]`: raw `cx, cy, w, h` (normalised 0–1) plus 13 sigmoid class scores, **no NMS in
the graph**. The app decodes it and runs class-aware NMS (conf 0.25, IoU 0.7). Classes:
`0 1000Rs · 1 100Rs · 2 10Rs · 3 20Rs · 4 5000Rs · 5 500Rs · 6 50Rs · 7 printed_year · 8 sbp_seal ·
9 security_dots · 10 security_lines · 11 security_thread · 12 serial_number`.

**Rs 5,000 genuine/counterfeit CNN:** converted PyTorch → ONNX → TFLite. The ImageNet
normalisation and softmax are built into the model, so the app feeds raw RGB 0–255. The class order
was read from the checkpoint: `{counterfeit: 0, genuine: 1}`. The training resize
(torchvision/Pillow bilinear) is reproduced in Dart **bit-exactly**. TFLite vs PyTorch: max
probability difference 2.4e-7.

**Monument classifier:** 224×224 letterbox, `x/127.5 − 1`, 8 outputs
(`monument_10 … monument_5000, invalid`). `monument_model_info.json` records its accuracy and
`"verified": true`.

SHA-256 of the committed model files:

| File | SHA-256 |
|---|---|
| `yolo11s_currency.tflite` | `d38dcf991514a471b665d687bde7440cc9e06f1eb79c0915378b1d142e1ce51e` |
| `monument_classifier.tflite` | `04163f8174730b752fec5440ce7e9b7978a5af1b09ff49b21e4503d7ed078496` |
| `rs5000_mobilenetv3large.tflite` | `2a4f8a062f49873cfbaba0ed805f422d9671a3c5ad2320706ed3fef62b47489c` |
| `mobilenetv3_pkr5000_counterfeit.tflite` | `d083ea2e980545dff24ac956c8bb4a48ec5eef7fb8ca20ba1039d6e02d3c9087` |

---

## Verification rules

Based on [`CURRENCY_RULES.MD`](CURRENCY_RULES.MD), with the project owner's corrections noted.

| Note | Lines / dots (front) | Security thread | Monument (back) | Extra |
|---|---|---|---|---|
| Rs 10 | none | none* | Bab-e-Khyber | |
| Rs 20 | lines | none* | Mohenjo-daro | |
| Rs 50 | lines (2 dashes) | none* | K2 | |
| Rs 100 | lines | 1 | Ziarat Residency | |
| Rs 500 | dots | 1 | Badshahi Mosque | |
| Rs 1000 | dots | 1 | Islamia College Peshawar | |
| Rs 5000 | dots | 1 | Faisal Mosque | edge microprint "5000", 2 CNNs |

\* Rs 10, 20 and 50 have **no security thread** (confirmed by the project owner; this overrides
the "every note has a thread" line in `CURRENCY_RULES`).

All notes: **1 SBP seal on the front, 3 on the back**, two serial numbers that must match character
for character, one printed year, and the same denomination on both sides.

How the rules are applied:

- A YOLO box **≥ 0.50** counts as confirmed. Boxes from 0.25 to 0.50 never count, but if they could
  explain a wrong count the check is *unclear* (UNABLE TO VERIFY) instead of *failed*.
- **Lines and dots are checked by type.** YOLO labels a whole group of dots or dashes as **one
  box**, so 1 to N boxes of the right type are accepted and the wrong type must be absent. The
  individual marks inside the box are counted from the pixels and shown as "2 of 2 counted".
- **Serials:** each YOLO serial box is read twice (plain and enhanced crop), as 2–3 letters + 7
  digits, with look-alike characters corrected by position. A reading that matches the other serial
  counts as a match. Two stable but different readings count as a **mismatch**. Anything unreliable
  → UNABLE TO VERIFY, never fake.
- **Thread:** front only (it is only labelled on fronts).
- **Low-quality images** (blur, glare, too dark or bright) → UNABLE TO VERIFY, never fake.
- **Microprint (Rs 5,000):** "5000" read ≥ 3× → pass; another value repeated → fail; unreadable →
  not checked, and the note can still pass ("Microprint unreadable – verified by alternate features").
- **Monument:** the right monument ≥ 0.60 → pass. Another monument or `invalid` ≥ 0.60 →
  **FAKE**, even if everything else passed. Below 0.60 → "Thora saaf photo lein, monument clear
  nahi" (never fails). The side pop-ups only trust the monument at ≥ 0.90.
- **Score:** weighted features (denomination 20, serial 25, seals 15, lines/dots 15, thread 10,
  year 5, each CNN 10, microprint 5, monument 20). A passing feature earns 85–100% of its weight.
  A critical failure (serial or denomination mismatch) is capped below 40%; any other failure below 85%.

---

## Results and verdicts

| Verdict | When |
|---|---|
| **PASSED APP CHECKS** (≥ 85%) | Every check that applies passed. This is not a certified authentication. |
| **SUSPICIOUS** | A feature is missing, wrong or mismatched, or a CNN flags the note |
| **JAALI NOTE / FAKE NOTE** | A note printed on paper ("Ye photocopy lag rahi hai"), or a confidently wrong back-side monument |
| **UNABLE TO VERIFY** | The photo or OCR is not reliable enough: retake |
| INCOMPLETE NOTE IMAGE | Half or cut-off note (shape checked against that note's real size, 65 mm tall, 115–163 mm long) |
| INVALID OBJECT | No banknote (YOLO finds no note with security features) |
| INCOMPLETE | Only one side scanned |

---

## Datasets and training

| Dataset | Used for | Where |
|---|---|---|
| YOLO dataset (13 classes) | YOLO11s | [Google Drive link](Data-Set/link%20of%20dataset.txt) |
| Monument dataset: 3,564 photos in folders by denomination, fronts and backs mixed, every angle | Monument classifier | Local `monument_photos/DataSet` (not committed: size) |
| Rs 5,000 counterfeit dataset | `mobilenetv3_pkr5000.pth` | Training notebooks in [`notebooks/`](notebooks/) |

**Monument classifier training** ([`fake_currency_detector/tools/train_monument.py`](fake_currency_detector/tools/train_monument.py)):

1. **Side sort with YOLO11s:** 1,210 backs (162–182 per note) → `monument_<value>`, 1,684 fronts →
   `invalid`, 670 unclear left out. Spot-checked by eye: all samples correct.
2. **Training:** MobileNetV2 with ImageNet weights, letterbox 224, augmentation (90° rotations,
   ±12° rotation, scale, light, blur, JPEG), 10 epochs + 5 fine-tune epochs, class-weighted.
3. **Honest test split:** whole photo bursts (same minute) are kept out of training.

| Class | Test photos | Accuracy |
|---|---|---|
| Rs 10 · Bab-e-Khyber | 33 | 100% |
| Rs 20 · Mohenjo-daro | 40 | 100% |
| Rs 50 · K2 | 37 | 100% |
| Rs 100 · Ziarat Residency | 38 | 100% |
| Rs 500 · Badshahi Mosque | 41 | 100% |
| Rs 1000 · Islamia College | 49 | 100% |
| Rs 5000 · Faisal Mosque | 50 | 100% |
| `invalid` (fronts) | 339 | 98.5% |

No monument was ever confused with another monument. The 5 errors were worn Rs 10 fronts read as
Rs 10 backs. All test photos come from the same dataset, so accuracy on new notes and phones is
expected to be somewhat lower.

Retrain with new photos:

```bash
python tools/train_monument.py --labelled ../monument_photos/DataSet
```

The script installs the new model into `assets/models/` (only marked `verified` at ≥ 90% per class).
Step-by-step guide: [`fake_currency_detector/docs/MONUMENT_MODEL_TRAINING.md`](fake_currency_detector/docs/MONUMENT_MODEL_TRAINING.md).
YOLO parity tool (`.pt` vs TFLite vs app): [`fake_currency_detector/tools/yolo_parity.py`](fake_currency_detector/tools/yolo_parity.py).

---

## Repository layout

```
.
├── fake_currency_detector/        ← current app (FYP-2)
│   ├── lib/
│   │   ├── core/                  theme, glass/neon widgets, haptics, network
│   │   └── features/
│   │       ├── scanner/           ML Kit capture, gallery free crop, front/back flow,
│   │       │                      microprint close-up camera
│   │       └── verification/
│   │           ├── data/          models (JSON), on-device pipeline: YOLO decoder,
│   │           │                  OCR parser, CNNs, monument, paper / half-note / side checks
│   │           ├── domain/        CurrencyRules, VerificationEngine, use case
│   │           └── presentation/  analyzing screen, diagnostic report, gauge, dialogs
│   ├── assets/models/             the 4 TFLite models + monument labels / info
│   ├── test/                      unit and widget tests
│   ├── tools/                     train_monument.py, yolo_parity.py
│   ├── docs/                      MONUMENT_MODEL_TRAINING.md
│   └── README.md                  detailed technical notes (integration checklists, thresholds)
├── app/                           first prototype (single MobileNetV3-Small classifier, scan history)
├── model/                         first prototype's model
├── notebooks/                     training notebooks
├── scripts/                       conversion script
├── docs/                          project documentation and meeting notes
├── Data-Set/                      dataset download link
└── CURRENCY_RULES.MD              verification rules (Word document)
```

---

## Build and run

Requirements: Flutter 3.47+ (Dart 3.13), Android SDK, JDK 17, an Android phone with Google Play
services.

```bash
cd fake_currency_detector
flutter pub get
flutter run --release                         # on a connected phone
flutter build apk --release --split-per-abi   # APKs in build/app/outputs/flutter-apk/
```

Install `app-arm64-v8a-release.apk` on most phones (about 106 MB; the models take about 67 MB).

Notes:

- `android/app/build.gradle.kts` pins `ndkVersion = "30.0.16248370"` (the NDK installed on the
  development machine). Change it to `flutter.ndkVersion` if needed.
- R8 shrinking is **off** for release, because it broke ML Kit at runtime.
- Permissions: camera (close-up camera) and internet (only for the optional server repository,
  which is not used by default).

---

## Tests

```bash
cd fake_currency_detector
flutter test
```

167 tests cover:
- the verification engine and score rules;
- uncertain YOLO counts;
- YOLO decoding and NMS, letterbox and channels-first layout;
- the Pillow-exact resize;
- serial OCR parsing and two-pass reconciliation;
- lines and dots by type, mark counting;
- paper, half-note and front/back detection;
- microprint;
- the monument classifier logic and trust levels;
- the result widgets.

---

## Known limitations

- **Watermark and see-through register are not checked.** YOLO11s has no class for them.
- **Thread recall:** YOLO sometimes misses the windowed thread (seen on a Rs 1,000). Faint
  detections give UNABLE TO VERIFY rather than a failure.
- **Foreign notes:** YOLO only knows PKR classes. A foreign note is expected to fail the PKR rules
  (SUSPICIOUS) but is not called "foreign".
- **Microprint** often needs the close-up, because micro-letters are ≈ 5–7 px in a full-note scan.
- **Test data:** model accuracies were measured on held-out photos from the project datasets, not
  yet on a separate field test with many phones.
- **"PASSED APP CHECKS"** means the note passed this app's programmed checks; it is not a bank-grade
  authentication.

---

## Academic project metadata

- **Project Title**: Counterfeit Currency Detection System
- **Academic Program**: Final Year Project (FYP-2)
- **Department**: Department of Computer Science
- **Academic Term**: 2025 – 2026

### Project team and roles
| Name | Project Role | Primary Focus |
| :--- | :--- | :--- |
| **M. Junaid Khan** | Project Supervisor | Academic Oversight & Architectural Guidance |
| **Abdul Manan Kaleem** | Lead Developer | Mobile Application Engineering, Hardware Integration & Preprocessing |
| **Raja Waleed** | Machine Learning Specialist | Neural Network Training, Optimization & TFLite Conversion |
| **M. Usman** | QA & Documentation Lead | System Testing, Dataset Verification & Technical Documentation |

---

*Developed at the Department of Computer Science: accessible, privacy-preserving AI tools for financial security.*
