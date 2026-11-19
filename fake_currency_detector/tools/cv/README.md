# 10-fold cross-validation tools

Scripts that test how well each model works on photos it has never seen.

| File | What it does |
|---|---|
| `cv_common.py` | Shared fold rules: one copy per source photo, photos of the same minute stay together, stratified, seed 7 |
| `cv_rs5000.py` | Rs 5,000 genuine vs altered, MobileNetV3-Large (PyTorch), patch level |
| `cv_yolo.py` | YOLO11s denomination detector (Ultralytics), reduced CPU budget |
| `cv_mnv3small.py` | MobileNetV3-Small genuine/fake (needs the Genuine and Fake folders; not part of the current run) |
| `alter_funcs.py` | The notebook's own alteration functions (blur, noise, brightness, contrast, colour shift, texture, obstruction) |
| `build_final_report.py` | Builds the final report (Markdown + PDF) from the three result files; refuses to run unless all 10 folds are present |
| `build_cv_report.py` | Builds the earlier draft report (Word + PDF) |

The monument test lives in `../train_monument.py` (`--folds 10`).

## Run (from `fake_currency_detector/`)

```bash
python tools/train_monument.py --sorted DataSet_sorted --folds 10 --cv-report cv_monument.json
python tools/cv/cv_rs5000.py --data DataSet/5000 --out cv_rs5000.json
python tools/cv/cv_yolo.py --data LargeDataset --work monument_work --out cv_yolo.json --max-train 1500
python tools/cv/build_final_report.py --results . --out .
```

Install once: `pip install torch torchvision ultralytics scikit-learn opencv-python-headless pandas matplotlib markdown tensorflow`.

Every script saves each finished fold, so a stopped run resumes where it stopped when started again with the
same command.

## What each test measures

- **Monument**: 8 classes (monument of Rs 10, 20, 50, 100, 500, 1000, 5000, and "invalid"). Metric: accuracy.
- **Rs 5,000**: one cell of the 8 x 4 patch grid, genuine or after a synthetic localised alteration. On a whole
  photo the alteration covers under 1% of the pixels, so the test works at patch level.
- **YOLO11s**: the 7 denomination boxes only (no security-feature boxes in the available data). Metrics:
  precision, recall, mAP@0.50, mAP@0.50-0.95. Trained from COCO weights at 320 px for 5 epochs on at most
  1,500 photos per fold, because the machine has no GPU.

## Limits

- The cross-validation models are fresh models, not the exact weights inside the app.
- Alterations in the Rs 5,000 test are synthetic; real counterfeits differ.
- Real-world photos (other phones, lighting, worn notes) may score lower.
