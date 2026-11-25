# FYP viva notes: storage and the confidence score

## 1. Database or CSV for saving scans?

**Answer: SQLite database (what the app now uses), plus a CSV export button.**

| | SQLite (sqflite) | CSV file |
|---|---|---|
| Structure | Typed columns (number, text, date) | Everything is text |
| Safe writes | A scan is saved completely or not at all (transaction) | A power cut or app kill mid-write can leave a broken file |
| Reading / filtering | Query one scan, the newest 10, only FAKE, count per denomination | Must load and parse the whole file |
| Changing data | Delete or edit one row | Rewrite the whole file |
| Growth | Fast with thousands of rows | Gets slow and large |
| Mobile storage | Built for apps; private to the app | Needs file permissions and a folder the user can find |
| Reading it outside the app | Needs a tool | Opens in Excel at once |

Why SQLite is strictly better for this app: the data is a table of records with one row per scan, written
automatically in the background. That is exactly what a database is for. CSV is only better for *handing data
to someone else*, so the app does both: SQLite stores, the share button exports a CSV (UTF-8, opens in Excel).

Why it suits the defense in two days: the database code is small (about 150 lines), covered by automated tests,
and works with no setup or internet. In the viva you can say "the app keeps a local database of every scan and
exports it as CSV for analysis", and show the History screen.

What is saved per scan: timestamp, denomination, final result (REAL / FAKE / unable), confidence percentage,
raw score, penalty, the status of each feature (denomination, serials, SBP seals, dots/lines, thread, printed
year, **Quaid-e-Azam portrait**, **monument**, Rs 5,000 checks) and the reasons text. Table file:
`scan_history.db`, table `scans`.

## 2. Show 94-96% or force 100%?

**Keep the real value. Never force 100%.**

1. **It is the honest number.** The score says how strong the evidence is, not "100% sure". A fixed 100% would
   be a made-up figure, and examiners are told to look for exactly that.
2. **No real system is 100%.** The models themselves are not: YOLO11s test mAP@0.50 is 98.0%, MobileNetV3-Small
   test accuracy 96.7%, Rs 5,000 alteration classifier 94.3%. Showing 100% would contradict your own tables.
3. **It protects the user.** "100% genuine" invites people to stop checking. 95% with a feature list shows what
   was verified.
4. **It is not wasted.** The score is also how the app separates cases: 85% and above with no failed feature =
   REAL; lower, or any failure = FAKE. Forcing 100% would remove that signal.

Defense sentence: "The percentage is the strength of the evidence found, calculated from the confidence of each
detected feature. A real note scores 94 to 96% because each detector is confident but not absolutely certain."

## 3. How the score is calculated (from the code)

All in `verification_engine.dart` and `currency_rules.dart`.

**Step 1: each security feature is a check with a weight.**

| Check | Weight | | Check | Weight |
|---|---|---|---|---|
| Denomination | 20 | | Monument (back) | 20 |
| Serial numbers | 25 | | Quaid-e-Azam portrait (front) | 10 |
| SBP seals | 15 | | Surface check (Rs 5,000 only) | 10 |
| Dots / lines | 15 | | Genuine/counterfeit CNN (Rs 5,000 only) | 10 |
| Security thread | 10 | | Microprint (Rs 5,000 only) | 5 |
| Printed year | 5 | | | |

**Step 2: a passing check earns points from its confidence.**

`points = weight x (0.85 + 0.15 x (confidence - 0.5) / 0.5)`

- confidence 0.50 (the minimum accepted) gives 85% of the weight
- confidence 0.75 gives 92.5%
- confidence 1.00 gives 100%

A failed or unclear check earns 0.

**Step 3: raw score** = points earned / total weight of the checks that actually ran x 100. Checks that were
skipped or do not apply are removed from both sides, so they never help or hurt.

**Step 4: penalties.** A failed critical check (denomination, serial numbers, wrong monument, wrong portrait):
score x 0.45, capped at 39. Any other failed check: score x 0.7 for each failure, capped at 84.

**Step 5: verdict.** FAKE if any check failed or the score is below 85; otherwise REAL.
(UNABLE TO VERIFY only when a photo cannot be judged.)

Example, Rs 5,000, every check passes with detector confidence about 0.90: factor = 0.85 + 0.15 x 0.8 = 0.97,
so the score is about 97%. With confidences near 0.80 the factor is 0.94 and the score about 94%.

## 4. Where the missing 4-6% goes

The score reaches 100% only if *every* detector were 100% confident. The gap comes from:

1. **Detector confidence is below 1.0.** YOLO11s box scores for real features in the app's sample outputs are about 0.87-0.95, and the
   formula gives only part of the weight below 1.0. This is the main source of the 4-6%.
2. **The models are not perfect.** YOLO11s test: precision 96.8%, recall 98.0%; the weakest class is the security
   thread (mAP@0.50 88.8%). OCR (ML Kit) reads serial numbers with its own confidence.
3. **The environment.** Lighting, glare, blur, shadow, a tilted note, a creased or worn note, camera quality and
   JPEG compression all lower the detector confidence. The photos are resized (letterboxed to 640 x 640 for YOLO,
   224 x 224 for the classifiers), which loses fine detail such as the thin thread and microprint.
4. **The training data.** The datasets were taken by a limited number of phones and settings; notes or cameras
   unlike the training photos give lower confidence.
5. **Deliberate design.** The 0.85 starting factor means a feature that is only just confident cannot score as
   high as a very confident one, so close calls cannot look perfect.

The conversion to TensorFlow Lite is *not* a source of loss: the float32 models were checked against the
originals (differences of 1e-7 to 1e-6).

## 5. What the new Quaid-e-Azam portrait check is (and is not)

It works like the monument check: a MobileNetV2 classifier looks at the front photo and says which note value's
front design it sees (or "invalid"). The app compares that with the denomination read by YOLO. A confident
mismatch makes the note FAKE; below 60% confidence it is "not checked".

- Trained on 1,688 front photos (7 values) and 1,217 backs as "invalid"; 100% on its 648 held-out test photos.
- **Honest limit:** it recognises the front *design* of each value. It is not a face-forgery detector, and the
  "invalid" class only contains backs. A good print of the right front would pass this check, which is why it is
  one check among many.
