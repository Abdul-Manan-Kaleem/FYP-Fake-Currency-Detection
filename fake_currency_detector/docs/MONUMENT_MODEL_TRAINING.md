# Training the back-side monument model

## Option A (recommended): the built-in pipeline, no labelling by hand

1. Put your photos, **unsorted**, in one folder, e.g. `FYP-2/monument_photos/`:
   backs of real notes (aim ≥ 30 per denomination), some fronts, some random objects.
2. Run (in the Python environment with tensorflow, numpy, pillow):

```bash
python tools/train_monument.py --photos ../monument_photos --sort-only
```

   YOLO11s sorts them into `monument_photos_sorted/<class>/` and writes `sort_report.csv`.
   **Check the folders**, move any wrong photo, then train and install:

```bash
python tools/train_monument.py --sorted ../monument_photos_sorted
```

   This writes `monument_classifier.tflite`, `monument_labels.txt` and
   `monument_model_info.json` into `assets/models/`. The model is marked **verified** only if every
   class reaches ≥ 90% on held-out photos (≥ 8 per class). Unverified models only show
   **warnings** in the app and are not used for the side pop-ups.
3. Rebuild the APK.

## Option B: Teachable Machine

The app already contains the monument check. It only needs the trained model:

```
assets/models/monument_classifier.tflite
assets/models/monument_labels.txt
```

Until those two files exist, the "Backside Monument" row shows *not installed* and nothing fails.

## 1. Collect photos

The 8 class names must be **exactly** these (the app maps them to denominations):

| Class name | What to photograph |
|---|---|
| `monument_10` | **Back** of real Rs 10 notes (Bab-e-Khyber) |
| `monument_20` | **Back** of real Rs 20 notes (Mohenjo-daro) |
| `monument_50` | **Back** of real Rs 50 notes (K2) |
| `monument_100` | **Back** of real Rs 100 notes (Quaid-e-Azam Residency, Ziarat) |
| `monument_500` | **Back** of real Rs 500 notes (Badshahi Mosque) |
| `monument_1000` | **Back** of real Rs 1000 notes (Islamia College Peshawar) |
| `monument_5000` | **Back** of real Rs 5000 notes (Faisal Mosque) |
| `invalid` | Everything else (see below) |

**At least 50 photos per class. 100+ is much better** (50 is the minimum that works, not a target).

For the 7 monument classes, use variety, or the model will only work in your room:
- several different notes per denomination (old and new, clean and worn)
- different phones, including a low-end one like the Infinix Hot 30
- different light: daylight, tube light, dim; some with slight glare
- different backgrounds and small rotations (±15°)
- **use the app's own scanner** (ML Kit crop) for most of them, so training photos look like what
  the app sees

For `invalid` (very important, because the app also uses this model to tell front from back):
- the **front** (Quaid-e-Azam side) of every denomination
- blurry, half and very dark note photos
- photocopies / printouts of notes
- random objects: paper, phone screens, hands, a table

## 2. Train

1. Open https://teachablemachine.withgoogle.com → **Get Started** → **Image Project** →
   **Standard image model**.
2. Rename the classes to the 8 names above and add the 8th class (`invalid`).
3. Upload the photos into each class (**Upload** → choose files).
   Teachable Machine crops every image to a centre square; the app does the same.
4. **Train Model.** Under *Advanced*: 50 epochs, batch size 16, learning rate 0.001 are good
   starting values.
5. Test in the preview with notes that were **not** used for training. Each back should show
   its own class at > 90%, and fronts should show `invalid`.

## 3. Export to the app

1. **Export Model** → **TensorFlow Lite** tab → **Floating point** → **Download my model**.
   (Quantized also works; floating point is more accurate.)
2. Unzip. You get `model_unquant.tflite` (or `model.tflite`) and `labels.txt`.
3. Copy them into the app and rename:
   - `model_unquant.tflite` → `fake_currency_detector/assets/models/monument_classifier.tflite`
   - `labels.txt` → `fake_currency_detector/assets/models/monument_labels.txt`
4. Rebuild:

```bash
flutter build apk --release --split-per-abi
```

Add a `monument_model_info.json` containing `{"verified": true}` only after testing it on real
notes yourself; without it the app treats a Teachable Machine model as **unverified** (warnings only).

The app reads the input size (224×224) and the input type from the model itself, applies the
same centre-square crop and `x / 127.5 − 1` scaling as Teachable Machine, and checks that the
number of outputs matches `labels.txt`. If something does not match, the log says
`Monument model not available: …` and the check stays *not installed*.

## 4. How the app uses it

| Model output on the back | Result |
|---|---|
| The note's own monument, ≥ 0.60 | **PASS**: "Back side verified – Ziarat Residency matched" |
| Another monument or `invalid`, ≥ 0.60 | **FAIL → verdict FAKE**: "Fake Note – Backside monument mismatch. 100 rupay pe Ziarat Residency honi chahiye" / "Back side galat hai – Ye 100 ka asli note nahi lag raha" |
| Anything below 0.60 | **Not checked**: "Thora saaf photo lein, monument clear nahi" (never fails) |

Right after the back is scanned, a confident monument of a **different** denomination than the
front shows "Ye 5000 ka note hai, aap 1000 scan kar rahe hain" and the photo is not kept.

**Before trusting FAKE verdicts, test the model on real notes.** A model that confuses two
monuments would label real notes as fake. Check every denomination's back on at least 10 notes
that were not in training.
