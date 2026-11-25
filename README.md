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

1. **Capture** both sides with the ML Kit document scanner (or gallery, or basic camera). After each
   photo the app checks it is a banknote and that it is the right side.
2. **Detect** the denomination and six features (printed year, SBP seal, security dots, security lines,
   security thread, serial number) with **YOLOv11s**.
3. **Read** the two serial numbers and the printed year with ML Kit text recognition.
4. **Classify** with MobileNetV3 Large models: two for Rs5,000 notes (alteration and genuine/counterfeit).
   (`kSmallCnnEnabled` in `currency_rules.dart`).
5. **Check the monument** printed on the back against the denomination.
6. **Decide** with a rule engine that returns one of: PASSED APP CHECKS, UNABLE TO VERIFY,
   FAKE, INCOMPLETE, or NOT A BANKNOTE. A poor photo or a missed
   detection is never reported as a counterfeit.

Everything runs on the phone through TensorFlow Lite.

## Recorded model results

Taken from the training notebooks in this repository (test sets of each model):

| Model | Task | Result |
|---|---|---|
| YOLO11s | Denominations and 6 features (348 usable test images) | mAP@0.50 0.9803, mAP@0.50:0.95 0.8722 |
| MobileNetV3-Large | Rs5,000 genuine vs synthetically altered (141 images) | Accuracy 0.9123, ROC AUC 0.9886 |
| Monument classifier | Building on the back, 7 monuments + invalid | 1.000 per monument, 0.985 invalid |

These are model scores on their own test sets, not the accuracy of the whole app on real notes.

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
`tools/cv/build_final_report.py` once all three tests have finished.

## Repository layout

```
fake_currency_detector/   Flutter app (current)
  lib/                    App source code, commented file by file
  assets/models/          The TensorFlow Lite models bundled in the APK
  test/                   Automated tests (176 test cases)
  tools/                  Training and parity helper scripts
  tools/cv/               10-fold cross-validation scripts and report builder
  docs/cv_report/         10-fold cross-validation report (draft, Word + PDF)
notebooks/                Earlier training notebooks and code for model trained in app
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

Group Members:
Muhammad Usman (40198)
Abdul Manan Kaleem (55762)
M. Waleed bin Naeem (46541)

Supervisor:
Mr. Junaid Khan.
