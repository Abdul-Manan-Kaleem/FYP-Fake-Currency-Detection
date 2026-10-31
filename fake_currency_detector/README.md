# Fake Currency Detector — Flutter client (FYP Part 2)

Scans both sides of a Pakistani banknote, sends them for detection
(YOLO11s + OCR + MobileNetV3), and applies the project rules from
`CURRENCY_RULES` **on the client** to produce a verdict and an authenticity
confidence percentage. State lives only in memory: no database, no auth, no telemetry.

## Run

```bash
flutter pub get
flutter run
```

All analysis runs **on the phone**. There is no mock data and no server.

## Roles: three models, kept separate

| Model | Role | Never used for |
|---|---|---|
| **YOLO11s** `assets/models/yolo11s_currency.tflite` | Is there a banknote; which of the 7 denominations (front and back); locates and counts SBP seals, security thread, lines, dots, serial-number regions and printed year | Reading text, alteration scoring |
| **ML Kit OCR** | Reads the text **inside** YOLO's serial-number and printed-year boxes; both serials are compared character by character | Finding features, deciding denomination |
| **Rs 5,000 CNN** `assets/models/rs5000_mobilenetv3large.tflite` | Synthetic-visual-alteration score, **only** when YOLO says both sides are Rs 5,000. Supporting evidence only | Any other denomination, feature counting |
| **Rs 5,000 genuine/counterfeit CNN** `assets/models/mobilenetv3_pkr5000_counterfeit.tflite` | Second, independent classifier from `mobilenetv3_pkr5000.pth`: P(counterfeit) for each side, **only** for Rs 5,000. Supporting evidence; ≥ 0.5 on either side fails its check | Any other denomination, feature counting |

`VerificationEngine` combines these outputs using the rules in `CURRENCY_RULES` and returns
**PASSED APP CHECKS**, **SUSPICIOUS** or **UNABLE TO VERIFY**. The capture flow can also
return INCOMPLETE (one side only) or INVALID OBJECT.

- **INVALID OBJECT** requires more than a note class. On test images, YOLO labelled a beige
  striped graphic "500Rs Note 0.79" and a page of printed text "100Rs Note 0.48", each as one
  box covering the whole frame, but found no security features on either. So a side counts as
  a note only when YOLO also finds at least 2 kinds of security feature on the front and at
  least 1 on the back (`note_presence.dart`).

- A YOLO box at or above **0.50** counts as confirmed. Boxes from 0.25 to 0.50 are *uncertain*:
  they never count, but if they could explain a wrong count the check becomes "unclear"
  (UNABLE TO VERIFY) instead of "failed" (SUSPICIOUS).
- The front is checked for 1 seal, the thread (where the note has one), the denomination mark,
  2 serial regions and 1 printed year. The back is checked for its denomination and 3 seals.
- **Security thread:** judged on the **front only**. The thread is only labelled on front
  images (confirmed by the project owner), so a thread box on the back is ignored.
  Only Rs 100, 500, 1000 and 5000 have one. Rs 10, 20 and 50 show
  "N/A" (confirmed by the project owner; this overrides the "every denomination has a thread"
  line in `CURRENCY_RULES`).
- **Denomination mark by type:** Rs 20/50/100 must show security *lines* and no dots.
  Rs 500/1000/5000 must show security *dots* and no lines. Rs 10 must show neither.
  YOLO11s labels a whole group of marks as **one box** (on device, both Rs 1,000 dots
  were inside one `security_dots` box), so 1 to N regions are accepted. Box count is
  not mark count. The individual marks inside the box are counted from the pixels
  (Otsu threshold + connected blobs, `ImagePreprocessor.countMarksIn`) and shown as
  supporting detail, e.g. "2 of 2 counted". That count never fails a note on its own.
- **Serial OCR:** each YOLO serial box is cropped with wide margins and read **twice**
  (plain crop + enhanced grayscale/contrast/enlarged crop). All OCR lines in a crop are
  joined, so letters and digits split across lines still form one serial. The serial is
  taken as 2–3 letters + 7 digits, and look-alikes are corrected by position (O→0 in the
  digits, 7→T in the letters…). `NoteTextParser.reconcile`:
  - if any read of serial #1 equals any read of serial #2 → **match**;
  - if each serial reads the same both times but they differ → **mismatch** (SUSPICIOUS);
  - otherwise → OCR unreliable → **UNABLE TO VERIFY**, never fake.

  The serial tile lists the raw text of every OCR pass.
- **Faint evidence:** if a required class produced no box (< 0.25) but still scored ≥ 0.10
  somewhere, the check is *unclear* (UNABLE TO VERIFY · retake), not *failed*. The per-class
  maximum scores are printed in the log (`YOLO class max front/back`).

## Edge microprint (Rs 5,000 only for now), no training

The Rs 5,000 note repeats "5000" in tiny text along its border. **For now the check runs only
on Rs 5,000** (project owner's request). Other notes, including Rs 1,000, have no microprint row
and skip the extra full-resolution work entirely. The expected text is known, so plain OCR is
enough:

1. **Automatic:** the four border bands (10% of the short side) are cut from the
   **full-resolution** capture (not the 2,048 px working copy). Side bands are turned flat,
   all bands are enlarged to ≥ 180 px tall, and ML Kit reads them on both sides.
2. **Close-up (optional):** if the scan is too small to read, the results screen offers
   "Check microprint close-up". It opens the phone camera, where you can zoom 2–3× and tap to
   focus, then re-reads the text and re-scores the note. All other model outputs stay the same.

Rules (`MicroprintRules`, `VerificationEngine._microprint`): the expected value read ≥ 3 times →
**PASS**. Repetition is what separates microprint from a single corner numeral. A *different*
denomination clearly repeated (≥ 3×) with the expected one absent → **FAIL**. Unreadable →
**not checked** (never fake). To add another note later, add it to
`CurrencyRules.microprintDenominations` and extend the Rs 5,000-only preparation step.

Physical limit: micro-letters are ≈0.2–0.3 mm tall, which is only ≈5–7 px in a full-note scan.
OCR needs ≈20 px, so on many phones only the close-up can read them.

## Front / back check right after each scan (all notes)

Each captured side is prepared and run through YOLO11s **immediately** (`scanSide`, cached
per photo), and `NoteSideRules` decides the side:
- **front** (Quaid-e-Azam side): ≥ 2 kinds of front-only feature (serial number, printed
  year, thread, lines, dots), each scoring ≥ 0.35
- **back** (building side): ≥ 2 SBP seals and no front-only feature
- otherwise **unknown**: the photo is kept and the full analysis decides

Wrong side → vibration + pop-up, and the photo is not kept:
- back in the FRONT step: "Ye note ki back side hai! Barah-e-meherbani pehle front side (Quaid wali side) scan karen."
- front in the BACK step: "Aap ne ye side pehle hi scan kar li hai…" (front already scanned),
  otherwise "Ye front side hai, ab back side (Building wali side) scan karen."

The same cached scan is reused by "Analyze", so most of the work is already done while the user
flips the note.

## Backside Monument Verification (all notes, needs a trained model)

Each back is classified by an **optional** Teachable Machine / MobileNet model
(`assets/models/monument_classifier.tflite` + `monument_labels.txt`; 8 classes `monument_10`
… `monument_5000`, `invalid`). Training steps: [docs/MONUMENT_MODEL_TRAINING.md](docs/MONUMENT_MODEL_TRAINING.md).
Without the files the check shows *not installed* and nothing breaks (the whole `assets/models/`
folder is bundled, so adding the files and rebuilding is enough).

- own monument ≥ 0.60 → PASS "Back side verified – <monument> matched"
- other monument / `invalid` ≥ 0.60 → FAIL and the verdict becomes **FAKE**, even if every other
  check passed ("Fake Note – Backside monument mismatch. 100 rupay pe Ziarat Residency honi chahiye")
- below 0.60 → not checked: "Thora saaf photo lein, monument clear nahi" (never fails)
- **Trust level:** `monument_model_info.json` (`"verified": true`) is written by
  `tools/train_monument.py` only when every class is ≥ 90% accurate on held-out photos. An
  unverified model never makes a note FAKE: a mismatch is a **WARNING** row that doesn't change
  the score, and the model is not used for the side / wrong-note pop-ups.
- **Installed model (verified):** trained by `tools/train_monument.py --labelled` on the project
  dataset `monument_photos/DataSet` (3,564 photos, fronts and backs mixed, folders by
  denomination). YOLO11s split the sides: 1,210 backs (162–182 per note), 1,684 fronts
  (`invalid`) and 670 unclear (left out). MobileNetV2, 224 letterbox, 10 + 5 fine-tune epochs, test
  set = whole photo bursts never seen in training. Held-out accuracy: every monument 100%
  (33–50 photos each, no monument ever confused with another), `invalid` 98.5% (5 of 339 worn
  Rs 10 fronts read as Rs 10 backs at 0.54–0.82). The app's Dart pre-processing matches the
  training input (mean difference 0.3%). Side / wrong-note pop-ups only trust the monument at
  ≥ 0.90; the monument check itself uses 0.60.
- weight 20 in the score. The requested "Watermark 30% + Thread 30% + Monument 40%" formula is
  not used, because the app has no watermark detector.
- The side check uses it too: a confident monument means back side, and a back whose monument
  belongs to another denomination than the front gives "Ye 5000 ka note hai, aap 1000 scan kar
  rahe hain".

## Photocopy → JAALI NOTE / FAKE NOTE (all notes)

If `PageDetector` finds printer paper (white border / page shape / blank paper) **and** YOLO
sees real note content on it (a note class ≥ 0.5 or any security feature), the result is the
red verdict **"Jaali Note / Fake Note – Ye photocopy lag rahi hai"**, with no "A4" message.
A page with no note content is still "not a note".

## Microprint close-up camera (Rs 5,000)

`MicroprintCameraScreen` (`camera` package) shows a guide box, a 1–3× zoom slider (starting
at 2×, so the phone can stay ≈10 cm away), auto-focus with tap-to-focus and a re-focus on the
box before the shot, and a torch that turns on automatically below **50 lux** (ambient light
sensor via `light`), or from frame brightness on phones without the sensor, plus a manual
torch button. The guide band is checked for sharpness (Laplacian variance ≥ 60). A blurry
photo shows "Focus clear nahi, thora qareeb layen aur mobile ko stable rakhen, roshni me
rakhen" with Retake / Use anyway.
Unreadable microprint never fails a note. A Rs 5,000 that passes everything else is PASSED
(≥ 85%) with the note "Microprint unreadable – verified by alternate features".
Limits: Flutter cannot select a phone's separate macro lens, and the app has no watermark or
see-through detector (YOLO has no such classes).

## Half / partial note rejection (all notes)

`PartialNoteDetector` runs after the paper check. All Pakistani notes are 65 mm tall and
8 mm longer per denomination (Rs 10 = 115 mm … Rs 5,000 = 163 mm), so each one has a known shape.
The scanner and the free crop cut the image at the note's edges. If the image shape is more
than 20% off the shape of the note YOLO sees, the side is rejected as
**INCOMPLETE NOTE IMAGE · HALF / PARTIAL NOTE DETECTED**, with instructions. That covers a left
or right half, three quarters, a top or bottom strip, and crops with a lot of background. When
YOLO is not sure of the denomination (< 0.5), the generic range 1.6–2.9 : 1 is used.

## Speed

Each photo is decoded **once** with the platform's native codec, already scaled to the
2,048 px working size, and kept in memory for YOLO, both CNNs, the OCR crops and mark counting.
OCR crops and microprint strips are written as BMP (nothing to compress). Measured on a
12-megapixel JPEG: old pure-Dart decode + re-encode + decode **3,530 ms** per side → new
native decode + all model inputs **548 ms** per side. Rs 5,000 microprint OCR stops as soon as
"5000" has been read 3 times.

## Gallery / camera crop

The crop screen uses a **free** crop frame: drag the corners onto the note edges and zoom in or
out freely. The old frame was locked to 1.8 : 1, which forced the photo to fill it and blocked
zooming out below ≈87%.

## Paper / A4 page rejection

`PageDetector` runs right after YOLO, before any other check. A side is rejected as
**NOT A PROPER IMAGE · PAPER / A4 PAGE DETECTED**, with step-by-step instructions, when:
- it is page-shaped (1.25–1.50 : 1, the shape of A4 or letter paper) **and** ≥ 25% of it is blank
  paper (bright, colourless pixels), or
- it is page-shaped and YOLO's note box covers < 60% of it (a note printed on a page or a
  photocopy), or
- ≥ 45% of it is blank paper, whatever its shape.

Real notes come out of the ML Kit scanner at ≈1.8–2.4 : 1 and are printed edge to edge.
Every scan logs `Paper check: … aspect … white …` so the thresholds can be checked on
real photos.

## Rs 5,000 genuine/counterfeit CNN integration record (`.pth`)

| Step | Result |
|---|---|
| Checkpoint | Folder `mobilenetv3_pkr5000` re-zipped to `.pth` (17,004,384 B, SHA-256 `1becbe94…3668`). Contains `model_state_dict`, `class_to_idx`, `class_names`, `image_size`. |
| Load | torchvision `mobilenet_v3_large`, `classifier[-1] = Linear(1280, 2)`, `load_state_dict(strict=True)` → **all keys matched**. |
| Class order | Read from the checkpoint, not guessed: `{'counterfeit': 0, 'genuine': 1}`. |
| Pre-processing (guide) | RGB → `Resize((224,224))` (Pillow bilinear, antialiased) → `ToTensor` → ImageNet mean/std. The app ports Pillow's resize to Dart (`pilBilinearRgb`); it is **bit-exact** against real Pillow output (`test/pil_resize_test.dart`). Normalisation and softmax are **baked into the model**, so the app feeds raw 0–255 RGB. |
| Conversion | PyTorch → ONNX (opset 17; torch vs ONNX Runtime max diff 1.2e-7) → onnx2tf → float32 TFLite, `[1,224,224,3]` → `[1,2]`, 16.8 MB, SHA-256 `d083ea2e…9087`. The float16 export does not load in the TFLite runtime, so it is not used. |
| Parity | TFLite vs PyTorch on 8 test images: **max probability difference 2.4e-7, same class 8/8**. |
| Caveat | A two-class model always answers one of its two classes. Non-note images score "counterfeit" ≈0.93–0.97, so it only runs **after** YOLO has confirmed Rs 5,000 on both sides. |

## YOLO11s integration record (TFLite checklist)

| # | Item | Result |
|---|---|---|
| 11 | Backups and hashes | `YOLOv11 model.tflite` 37,969,708 B, SHA-256 `d38dcf991514a471b665d687bde7440cc9e06f1eb79c0915378b1d142e1ce51e`. `rs5000_mobilenetv3large.tflite` 3,437,832 B, SHA-256 `2a4f8a062f49873cfbaba0ed805f422d9671a3c5ad2320706ed3fef62b47489c`. Bundled copies are byte-identical. **The `.pt` was not provided.** |
| 12 | Tensors | Input `float32[1,3,640,640]`, **channels-first (BCHW)**, not quantized. Output `float32[1,17,8400]`. |
| 13 | Output format | **Raw head, no NMS** (`end2end: false`). Read from the graph: DFL → xywh → × stride → sigmoid on the 13 class scores → `_NormalizeCoords` × 1/640. Boxes are **cx, cy, w, h normalized 0–1**. The app runs the decode and the NMS itself (conf 0.25, IoU 0.7, class-aware, max 300 = Ultralytics `predict` defaults). Confirmed by running the model in TF 2.21: the box channel max is 1.00 and class scores are 0–1. |
| 14 | Pre-processing | EXIF-corrected **RGB**, letterbox to 640 keeping the aspect ratio, grey **114** padding centred, /255, planar CHW. The same steps are in `tools/yolo_parity.py`. |
| 15 | Class IDs | From the embedded `metadata.json`: 0 1000Rs, 1 100Rs, 2 10Rs, 3 20Rs, **4 5000Rs Note**, 5 500Rs, 6 50Rs, 7 printed_year, 8 sbp_seal, 9 security_dots, 10 security_lines, 11 security_thread, 12 serial_number. Unit-tested. |
| 16 | All denominations, rotated, challenging | **To do on device**: needs real note photos |
| 17 | `.pt` vs TFLite vs Flutter | Run `python tools/yolo_parity.py photo.jpg --tflite yolo11s_currency.tflite --pt best.pt` in Colab and compare with the app's `YOLO front/back` log lines (same format) |
| 18 | Device latency | Shown at the bottom of every results screen (`preprocess`, `yolo_front`, `yolo_back`, `ocr`, `cnn`, `total` in ms), and also in the log |
| 19 | Size | Release `app-arm64-v8a-release.apk` **76 MB** (`flutter build apk --release --split-per-abi`). YOLO accounts for 36 MB. |

### Rs 5,000 CNN contract

Input `float32[1,224,224,3]` RGB 0–255 (the model rescales internally). Output `float32[1,1]`
sigmoid `altered_probability`. It runs on both sides and the higher value is used; above 0.5 fails.

Both Rs 5,000 CNNs were **trained on front and back images** (confirmed by the project owner),
so each one scores both sides and the worse side decides.

## Structure

```
lib/
  core/            theme, glass/neon widgets, dio client, dev settings, haptics
  features/
    scanner/       ML Kit document scanner + gallery/crop, guided FRONT→flip→BACK→review flow
    verification/
      data/        JSON models, on-device repository (OCR + TFLite), optional API repository
      domain/      CurrencyRules, VerificationEngine (rules + scoring), use case
      presentation/ analyzing (radar) screen, results dashboard, gauge, "not a note" modal
```

## Optional server API contract (not used by default)

`POST /api/v1/verify`, multipart: `front_image`, `back_image` (JPEG).
The response holds raw detections (bare, or wrapped in `{"analysis": …}`):

```json
{
  "is_banknote": true,
  "banknote_confidence": 0.98,
  "front": {
    "quality": {"blur_score": 0.07, "glare_score": 0.05, "brightness": 0.56},
    "denomination": 5000, "denomination_confidence": 0.93,
    "sbp_seals":        {"count": 1, "confidence": 0.80},
    "security_threads": {"count": 1, "confidence": 0.80},
    "security_lines":   {"count": 0, "confidence": 0.90},
    "security_dots":    {"count": 3, "confidence": 0.87},
    "printed_year": {"detected": true, "value": "2022", "confidence": 0.85},
    "serial_numbers": [{"text": "AK4718263", "confidence": 0.89},
                       {"text": "AK4718263", "confidence": 0.88}]
  },
  "back": {
    "quality": {"blur_score": 0.07, "glare_score": 0.05, "brightness": 0.56},
    "denomination": 5000, "denomination_confidence": 0.92,
    "sbp_seals": {"count": 3, "confidence": 0.86},
    "security_threads": {"count": 1, "confidence": 0.88}
  },
  "anomaly": {"model": "MobileNetV3-Large", "anomaly_score": 0.16, "threshold": 0.5}
}
```

## Scoring (VerificationEngine)

Weights: Denomination 20, Serial OCR 25, SBP seals 15, Lines/Dots 15,
Thread 10, Year/Layout 5, MobileNetV3 10.

- A passing feature earns 85–100% of its weight, scaled by detection confidence.
  A note that passes every check therefore always scores ≥ 85%.
- Critical failure (serial or denomination mismatch): ×0.45, capped at 39%.
- Each other failed feature: ×0.7, capped at 84%.
- Score ≥ 85 with no failed check → PASSED APP CHECKS; anything lower → SUSPICIOUS (red when < 40).
- Poor image quality or any detection below 0.5 confidence (with no clear failure) gives UNABLE TO VERIFY at 0%.
- A single-side scan gives INCOMPLETE. No YOLO note class on a side opens the "INVALID OBJECT DETECTED" modal.

Tests: `flutter test`: 167 tests (engine rules, uncertain counts, YOLO decode/NMS, letterbox/CHW layout, Pillow-exact resize, OCR/serial parsing, microprint, paper detection).

## Platform notes

- ML Kit Document Scanner works on **Android only** (it needs Google Play services). On iOS, or if the
  scanner module is unavailable, the app falls back to camera + manual crop locked to 1.8:1.
- Release builds use `android/app/proguard-rules.pro` (ML Kit optional language packs, TFLite keep rules).
- `android/gradle.properties` sets `kotlin.jvm.target.validation.mode=warning` because `tflite_flutter` mixes JVM targets.
- `android/app/build.gradle.kts` pins `ndkVersion = "30.0.16248370"` because that is the NDK installed
  on this machine. Change it to `flutter.ndkVersion` if you install NDK 28.2.
