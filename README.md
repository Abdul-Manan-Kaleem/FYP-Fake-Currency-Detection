# Pakistani Currency Note Screening System

Final Year Project, Faculty of Computing, Riphah International University, Islamabad.

An Android app that screens a Pakistani banknote on the phone, with no server. The user photographs
**both sides** of a note. The app finds the denomination and the printed security features, reads and
compares the two serial numbers, adds classifier evidence, and shows a cautious result with the
reasons behind it.

> The app is a screening aid. **PASSED APP CHECKS** means the note passed this application's
> programmed checks. It is not an official authentication by the State Bank of Pakistan.

## The app

The current app is in **[`fake_currency_detector/`](fake_currency_detector/)**. Its own
[README](fake_currency_detector/README.md) has the full details. (The first-term prototype that used to
live in `app/` was removed; its history is still in git.)

How a note is checked:

1. **Capture** both sides with the ML Kit document scanner in base mode (crop and rotate only, no
   automatic filters), or gallery, or basic camera. After each photo the app checks it is a banknote and
   that it is the right side. Photos are **never enhanced automatically**: the original photo is checked
   by default. On the review screen an **Enhance photos** switch (OFF by default) lets the user turn
   enhancement ON or OFF at any time; ON checks enhanced copies, OFF goes back to the originals (the
   original files are never changed).
2. **Detect** the denomination and six features (printed year, SBP seal, security dots, security lines,
   security thread, serial number) with **YOLO11s**.
3. **Read** the two serial numbers and the printed year with ML Kit text recognition.
4. **Classify** with MobileNetV3 models: two for Rs5,000 notes (alteration and genuine/counterfeit). A
   MobileNetV3-Small model for Rs10 to Rs1,000 is built in but switched off for now
   (`kSmallCnnEnabled` in `currency_rules.dart`).
5. **Check the monument** printed on the back and the **Quaid-e-Azam portrait** on the front against the
   denomination (two small image classifiers; a confident mismatch is FAKE).
6. **Decide** with a rule engine. The verdict is only **REAL** or **FAKE**: any failed feature makes the
   note FAKE. UNABLE TO VERIFY, INCOMPLETE and NOT A BANKNOTE are shown only when the photos cannot be
   judged (a poor photo or a missed detection is never reported as a counterfeit). The result screen
   shows the verdict first, then the security-features list, then the scanned images.

Strict rules in the engine:

- **Dots / lines** (counted separately, on the original image): the note must show exactly Rs 10 none,
  Rs 20 one line, Rs 50 two lines, Rs 100 three lines, Rs 500 one dot, Rs 1,000 two dots, Rs 5,000
  three dots. Fewer or more, or the wrong mark type, fails the feature and the note is FAKE even if
  every other feature passes.
- **Serial number**: it must look random. Repeated digits (000000000, 111111111) or a pattern
  (1234567890, 9876543210, alternating digits) are FAKE.
- All messages are in English.

Everything runs on the phone through TensorFlow Lite.

## Recorded model results

Taken from the training notebooks in this repository (test sets of each model):

| Model | Task | Result |
|---|---|---|
| YOLO11s | Denominations and 6 features (348 usable test images) | mAP@0.50 0.9803, mAP@0.50:0.95 0.8722 |
| MobileNetV3-Large | Rs5,000 genuine vs synthetically altered (141 images) | Accuracy 0.9433, ROC AUC 0.9885 |
| MobileNetV3-Small | Rs10 to Rs1,000 genuine vs fake (332 images) | Accuracy 0.9669, ROC AUC 0.9961 |
| Monument classifier | Building on the back, 7 monuments + invalid | 1.000 per monument, 0.985 invalid |

These are model scores on their own test sets, not the accuracy of the whole app on real notes.

## Scan history

Every scan is saved automatically in a local SQLite database (time, denomination, result, confidence, the
status of each security feature). The History button on the capture screen lists the scans and exports them
as CSV. Study notes for the viva (database vs CSV, how the confidence score is calculated) are in
`fake_currency_detector/docs/VIVA_NOTES.md`.

## 10-fold cross-validation

How well each model works on photos it has not seen is measured with 10-fold cross-validation (ten fresh
models, each tested on the tenth of the photos it did not train on). Folds are stratified, grouped by
photo burst (same minute), de-duplicated (one copy per Roboflow source photo) and use seed 7.
Nothing is installed into the app.

| Test | Model | Script |
|---|---|---|
| Monument classifier (note back) | MobileNetV2 | `tools/train_monument.py --folds 10` |
| Rs 5,000 genuine vs altered (patch level) | MobileNetV3-Large | `tools/cv/cv_rs5000.py` |
| Note denomination detector | YOLO11s | `tools/cv/cv_yolo.py` |

Details, commands and limits are in [`fake_currency_detector/tools/cv/README.md`](fake_currency_detector/tools/cv/README.md).
A draft report is in `fake_currency_detector/docs/cv_report/`; the final numbers are produced by
`tools/cv/build_final_report.py` once all three tests have finished. MobileNetV3-Small is not part of this
run (its Genuine/Fake training photos are not available).

## Repository layout

```
fake_currency_detector/   Flutter app (current)
  lib/                    App source code, commented file by file
  assets/models/          The TensorFlow Lite models bundled in the APK
  test/                   Automated tests (176 test cases)
  tools/                  Training and parity helper scripts
  tools/cv/               10-fold cross-validation scripts and report builder
  docs/cv_report/         10-fold cross-validation report (draft, Word + PDF)
notebooks/                Earlier training notebooks
model/                    Earlier exported model files
monument_model_out/       Monument classifier labels and info
Data-Set/                 Link to the dataset
scripts/                  Python helper scripts
docs/                     Project documentation and meeting notes
CURRENCY_RULES.MD         The feature rules used for each denomination
```

## Run it

You need the Flutter stable SDK (3.50 or newer) and JDK 21 for the Android build.

```bash
git clone https://github.com/Abdul-Manan-Kaleem/FYP-Fake-Currency-Detection.git
cd FYP-Fake-Currency-Detection/fake_currency_detector
flutter pub get
flutter run                      # on a connected Android phone
flutter test                     # run the automated tests
flutter build apk --release --split-per-abi
```

The APKs are written to `fake_currency_detector/build/app/outputs/flutter-apk/`. To open the project in
Android Studio, open the `fake_currency_detector` folder.

## Cloud build

`.github/workflows/build_apk.yml` builds a release APK on GitHub Actions for pushes to `main` (or by hand
from the Actions tab) and uploads it as an artifact.

## Team

Muhammad Usman, Abdul Manan Kaleem and M. Waleed bin Naeem. Supervisor: Mr. Junaid Khan.
