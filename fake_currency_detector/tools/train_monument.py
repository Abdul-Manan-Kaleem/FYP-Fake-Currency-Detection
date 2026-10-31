"""Train the back-side monument classifier and install it into the app.

    python tools/train_monument.py --photos PHOTOS_DIR
    python tools/train_monument.py --sorted SORTED_DIR           # already sorted

1. AUTO-SORT (--photos): every photo (unsorted, any name) is run through the
   app's YOLO11s model with the app's own pre-processing:
     - back side (≥ 2 SBP seals, no front-only feature) with a confident note
       class → monument_<denomination>
     - front side (serials / year / thread / lines / dots) or no note → invalid
     - anything unclear → _unsure (not used; sort by hand if you want)
   Result: PHOTOS_DIR_sorted/<class>/… plus sort_report.csv. CHECK IT before
   trusting the model; move wrong files and re-run with --sorted.
2. TRAIN: MobileNetV2 (ImageNet weights, like Teachable Machine), 224×224,
   input scaled to [-1, 1], centre-square crop: the same input the app builds
   (MonumentClassifier.teachableMachineInput). Heavy augmentation (rotation,
   scale, light, blur, JPEG). 20% of the photos of every class are held out.
3. VERIFY: per-class accuracy on the held-out photos. The model is marked
   "verified" only if every class has ≥ MIN_TEST photos and ≥ 90% accuracy.
   Unverified models only produce warnings in the app, never FAKE.
4. EXPORT + INSTALL: float32 TFLite, checked against Keras, written to
   assets/models/ as monument_classifier.tflite, monument_labels.txt
   ("0 monument_10" format) and monument_model_info.json.

Requires: tensorflow, numpy, pillow.
"""
import argparse
import csv
import datetime
import io
import json
import os
import random
import shutil
import sys

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter, ImageOps

CLASSES = ['monument_10', 'monument_20', 'monument_50', 'monument_100',
           'monument_500', 'monument_1000', 'monument_5000', 'invalid']
DENOMS = {0: 1000, 1: 100, 2: 10, 3: 20, 4: 5000, 5: 500, 6: 50}   # YOLO note classes
FRONT_ONLY = {7, 9, 10, 11, 12}   # printed_year, dots, lines, thread, serial
SEAL = 8
SIZE = 224
MIN_TEST = 8
VERIFY_ACC = 0.90
IMG_EXT = ('.jpg', '.jpeg', '.png', '.bmp', '.webp')


# --------------------------------------------------------------- auto-sort --

def _yolo_interpreter(path):
    import tensorflow as tf
    it = tf.lite.Interpreter(model_path=path, num_threads=os.cpu_count())
    it.allocate_tensors()
    return it


def _yolo_detect(it, im):
    """Same as the app: cap 2048, letterbox 640 grey 114, /255, CHW."""
    long = max(im.size)
    if long > 2048:
        r = 2048 / long
        im = im.resize((round(im.width * r), round(im.height * r)), Image.BOX)
    r = min(640 / im.width, 640 / im.height)
    nw, nh = round(im.width * r), round(im.height * r)
    canvas = Image.new('RGB', (640, 640), (114, 114, 114))
    canvas.paste(im.resize((nw, nh), Image.BILINEAR), ((640 - nw) // 2, (640 - nh) // 2))
    x = (np.asarray(canvas, np.float32) / 255).transpose(2, 0, 1)[None]
    inp, out = it.get_input_details()[0], it.get_output_details()[0]
    it.set_tensor(inp['index'], x)
    it.invoke()
    raw = it.get_tensor(out['index'])[0]            # (17, 8400)
    scores = raw[4:]
    cls, best = scores.argmax(0), scores.max(0)
    keep = best > 0.25
    return [(int(c), float(s)) for c, s in zip(cls[keep], best[keep])]


def _side_and_denom(dets):
    strong = [(c, s) for c, s in dets if s >= 0.35]
    front_kinds = {c for c, _ in strong if c in FRONT_ONLY}
    seals = sum(1 for c, _ in strong if c == SEAL)
    notes = [(c, s) for c, s in dets if c in DENOMS]
    note = max(notes, key=lambda t: t[1]) if notes else None
    denom = DENOMS[note[0]] if note and note[1] >= 0.5 else None
    if len(front_kinds) >= 2:
        return 'front', denom
    if not front_kinds and seals >= 2:
        return 'back', denom
    return ('none' if not notes else 'unsure'), denom


def sort_labelled(dataset, yolo_path):
    """Folders already named by denomination (DataSet/10, DataSet/5000, …),
    fronts and backs mixed. The folder gives the denomination; YOLO11s only
    decides the side: back → monument_<folder>, front → invalid, unclear →
    _unsure (left out)."""
    out = dataset.rstrip('/\\') + '_sorted'
    it = _yolo_interpreter(yolo_path)
    rows, i = [], 0
    for denom in sorted(os.listdir(dataset)):
        folder = os.path.join(dataset, denom)
        if not os.path.isdir(folder) or not denom.isdigit():
            continue
        files = sorted(os.path.join(dp, f) for dp, _, fs in os.walk(folder)
                       for f in fs if f.lower().endswith(IMG_EXT))
        print(f'Rs {denom}: {len(files)} photos')
        for path in files:
            i += 1
            try:
                im = ImageOps.exif_transpose(Image.open(path)).convert('RGB')
            except Exception as e:  # noqa: BLE001
                rows.append((path, denom, 'unreadable', '', '', str(e)))
                continue
            side, yolo_denom = _side_and_denom(_yolo_detect(it, im))
            target = (f'monument_{denom}' if side == 'back'
                      else 'invalid' if side == 'front' else '_unsure')
            dest = os.path.join(out, target)
            os.makedirs(dest, exist_ok=True)
            name = f'{denom}_{os.path.basename(path)}'
            shutil.copy2(path, os.path.join(dest, name))
            rows.append((path, denom, side, yolo_denom or '', target, name))
            if i % 100 == 0:
                print(f'  {i} done', flush=True)
    with open(os.path.join(out, 'sort_report.csv'), 'w', newline='', encoding='utf8') as f:
        w = csv.writer(f)
        w.writerow(['photo', 'folder_denomination', 'yolo_side', 'yolo_denomination',
                    'class', 'file'])
        w.writerows(rows)
    summary = {}
    for _, d, side, _, _, _ in rows:
        summary.setdefault(d, {}).setdefault(side, 0)
        summary[d][side] += 1
    print('Sides per denomination:', json.dumps(summary, indent=1))
    return out


def auto_sort(photos, yolo_path):
    out = photos.rstrip('/\\') + '_sorted'
    it = _yolo_interpreter(yolo_path)
    rows = []
    files = [os.path.join(dp, f) for dp, _, fs in os.walk(photos) for f in fs
             if f.lower().endswith(IMG_EXT)]
    print(f'Auto-sorting {len(files)} photos with YOLO11s …')
    for i, path in enumerate(sorted(files)):
        try:
            im = ImageOps.exif_transpose(Image.open(path)).convert('RGB')
        except Exception as e:  # noqa: BLE001
            rows.append((path, 'unreadable', '', str(e)))
            continue
        side, denom = _side_and_denom(_yolo_detect(it, im))
        if side == 'back' and denom:
            target = f'monument_{denom}'
        elif side in ('front', 'none'):
            target = 'invalid'
        else:
            target = '_unsure'
        dest = os.path.join(out, target)
        os.makedirs(dest, exist_ok=True)
        shutil.copy2(path, os.path.join(dest, f'{i:05d}_{os.path.basename(path)}'))
        rows.append((path, target, side, denom or ''))
        if (i + 1) % 25 == 0:
            print(f'  {i + 1}/{len(files)}')
    with open(os.path.join(out, 'sort_report.csv'), 'w', newline='', encoding='utf8') as f:
        w = csv.writer(f)
        w.writerow(['photo', 'class', 'side', 'denomination'])
        w.writerows(rows)
    counts = {}
    for _, t, _, _ in rows:
        counts[t] = counts.get(t, 0) + 1
    print('Sorted:', json.dumps(counts, indent=1))
    print(f'Review {out} (and sort_report.csv) before trusting the model.')
    return out


# ------------------------------------------------------------- data + aug --

def load_image(path, max_side=1024):
    im = ImageOps.exif_transpose(Image.open(path)).convert('RGB')
    if max(im.size) > max_side:
        r = max_side / max(im.size)
        im = im.resize((round(im.width * r), round(im.height * r)), Image.BOX)
    return im


PAD = (114, 114, 114)


def letterbox_224(im):
    """Exactly what the app does (preprocess "letterbox"): keep the whole
    image, scale its long side to 224 (area filter), centre it on grey 114."""
    r = SIZE / max(im.size)
    w, h = max(1, round(im.width * r)), max(1, round(im.height * r))
    canvas = Image.new('RGB', (SIZE, SIZE), PAD)
    canvas.paste(im.resize((w, h), Image.BOX), ((SIZE - w) // 2, (SIZE - h) // 2))
    return canvas


def augment(im, rng):
    k = int(rng.integers(0, 4))
    if k:
        im = im.transpose([None, Image.ROTATE_90, Image.ROTATE_180, Image.ROTATE_270][k])
    w, h = im.size
    # Small perspective-free geometry: rotation + scale + shift.
    im = im.rotate(rng.uniform(-12, 12), resample=Image.BILINEAR, expand=False,
                   fillcolor=tuple(int(v) for v in rng.integers(0, 255, 3)))
    sc = rng.uniform(0.85, 1.0)
    cw, ch = int(w * sc), int(h * sc)
    x0, y0 = rng.integers(0, w - cw + 1), rng.integers(0, h - ch + 1)
    im = im.crop((x0, y0, x0 + cw, y0 + ch))
    im = ImageEnhance.Brightness(im).enhance(rng.uniform(0.6, 1.35))
    im = ImageEnhance.Contrast(im).enhance(rng.uniform(0.7, 1.3))
    im = ImageEnhance.Color(im).enhance(rng.uniform(0.7, 1.3))
    if rng.random() < 0.35:
        im = im.filter(ImageFilter.GaussianBlur(rng.uniform(0.5, 2.0)))
    if rng.random() < 0.5:
        buf = io.BytesIO()
        im.save(buf, 'JPEG', quality=int(rng.integers(35, 90)))
        im = Image.open(buf).convert('RGB')
    return im


def burst_key(path):
    """Photos taken in the same minute are near-duplicates; keep each burst
    entirely in train or entirely in test so accuracy is honest."""
    import re
    name = os.path.basename(path)
    m = (re.search(r'(\d{8})_(\d{4})\d{2}', name)                  # 20260812_161846
         or re.search(r'(\d{4}-\d{2}-\d{2}) at (\d{2}\.\d{2})', name)  # WhatsApp
         or re.search(r'IMG(\d{8})(\d{4})', name))                   # IMG20220209121614
    return '_'.join(m.groups()) if m else name


def build_dataset(sorted_dir, min_per_class, seed):
    rng = random.Random(seed)
    classes, files = [], {}
    for c in CLASSES:
        d = os.path.join(sorted_dir, c)
        fs = sorted(os.path.join(d, f) for f in os.listdir(d)
                    if f.lower().endswith(IMG_EXT)) if os.path.isdir(d) else []
        if len(fs) >= min_per_class:
            classes.append(c)
            files[c] = fs
        elif fs:
            print(f'  skipping {c}: only {len(fs)} photos (need {min_per_class})')
    if 'invalid' not in classes:
        sys.exit('Need an "invalid" class (fronts of notes, other objects).')
    if len(classes) < 2:
        sys.exit('Need at least one monument class with enough photos.')
    train, test = [], []
    for ci, c in enumerate(classes):
        groups = {}
        for f in files[c]:
            groups.setdefault(burst_key(f), []).append(f)
        keys = sorted(groups)
        rng.shuffle(keys)
        target = 0.2 * len(files[c])
        n = 0
        for k in keys:
            dest = test if n < target else train
            dest += [(f, ci) for f in groups[k]]
            if dest is test:
                n += len(groups[k])
    return classes, train, test


def materialise(items, augment_copies, seed):
    rng = np.random.default_rng(seed)
    xs, ys = [], []
    for path, y in items:
        im = load_image(path)
        xs.append(np.asarray(letterbox_224(im), np.uint8))
        ys.append(y)
        for _ in range(augment_copies):
            xs.append(np.asarray(letterbox_224(augment(im, rng)), np.uint8))
            ys.append(y)
    return np.stack(xs), np.array(ys)


def to_model_input(x_uint8):
    return x_uint8.astype(np.float32) / 127.5 - 1.0   # Teachable Machine scaling


# ------------------------------------------------------------------- train --

def train(sorted_dir, out_dir, install, min_per_class, epochs, seed):
    import tensorflow as tf
    tf.keras.utils.set_random_seed(seed)

    classes, train_items, test_items = build_dataset(sorted_dir, min_per_class, seed)
    per_class = {c: sum(1 for _, y in train_items + test_items if y == i)
                 for i, c in enumerate(classes)}
    print('Classes:', per_class)
    copies = max(1, min(20, 4000 // max(1, len(train_items))))
    print(f'Augmenting: {copies} extra copies per training photo …')
    xtr, ytr = materialise(train_items, copies, seed)
    xte, yte = materialise(test_items, 0, seed + 1)

    base = tf.keras.applications.MobileNetV2(
        input_shape=(SIZE, SIZE, 3), include_top=False, weights='imagenet', pooling='avg')
    base.trainable = False
    inp = tf.keras.Input((SIZE, SIZE, 3), name='image')   # already in [-1, 1]
    x = base(inp, training=False)
    x = tf.keras.layers.Dropout(0.25)(x)
    out = tf.keras.layers.Dense(len(classes), activation='softmax', name='probs')(x)
    model = tf.keras.Model(inp, out)

    counts = np.bincount(ytr, minlength=len(classes))
    class_weight = {i: len(ytr) / (len(classes) * max(1, n)) for i, n in enumerate(counts)}

    def ds(x, y, shuffle):
        d = tf.data.Dataset.from_tensor_slices((x, y))
        if shuffle:
            d = d.shuffle(len(x), seed=seed, reshuffle_each_iteration=True)
        return d.batch(32).map(
            lambda a, b: (tf.cast(a, tf.float32) / 127.5 - 1.0, b)).prefetch(2)

    train_ds, test_ds = ds(xtr, ytr, True), ds(xte, yte, False)

    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
                  loss='sparse_categorical_crossentropy', metrics=['accuracy'])
    model.fit(train_ds, epochs=epochs, validation_data=test_ds,
              class_weight=class_weight, verbose=2)
    # Fine-tune the top of the backbone.
    base.trainable = True
    for layer in base.layers[:-30]:
        layer.trainable = False
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-5),
                  loss='sparse_categorical_crossentropy', metrics=['accuracy'])
    model.fit(train_ds, epochs=max(3, epochs // 2), validation_data=test_ds,
              class_weight=class_weight, verbose=2)

    # ---- held-out evaluation
    pred = model.predict(test_ds, verbose=0).argmax(1)
    report, verified = {}, True
    for i, c in enumerate(classes):
        n = int((yte == i).sum())
        acc = float((pred[yte == i] == i).mean()) if n else 0.0
        report[c] = {'test_photos': n, 'accuracy': round(acc, 3)}
        if n < MIN_TEST or acc < VERIFY_ACC:
            verified = False
    confusion = np.zeros((len(classes), len(classes)), int)
    for t, p in zip(yte, pred):
        confusion[t, p] += 1
    print('\nHeld-out accuracy per class:')
    for c, r in report.items():
        print(f'  {c:15s} {r["accuracy"]:.3f}  ({r["test_photos"]} photos)')
    print('Confusion (rows = true, cols = predicted):', classes)
    print(confusion)
    print('VERIFIED' if verified else
          f'NOT verified (needs ≥ {MIN_TEST} test photos and ≥ {VERIFY_ACC:.0%} per class): '
          'the app will only show warnings.')

    # ---- export + parity
    tflite = tf.lite.TFLiteConverter.from_keras_model(model).convert()
    it = tf.lite.Interpreter(model_content=tflite)
    it.allocate_tensors()
    i_d, o_d = it.get_input_details()[0], it.get_output_details()[0]
    worst = 0.0
    for k in range(min(20, len(xte))):
        xk = to_model_input(xte[k:k + 1])
        it.set_tensor(i_d['index'], xk)
        it.invoke()
        worst = max(worst, float(np.abs(it.get_tensor(o_d['index'])[0] -
                                        model.predict(xk, verbose=0)[0]).max()))
    print(f'TFLite input {i_d["shape"]} {i_d["dtype"].__name__}, output {o_d["shape"]}; '
          f'Keras vs TFLite max |diff| {worst:.2e}')

    info = {
        'verified': verified,
        'classes': classes,
        'per_class': report,
        'images_per_class': per_class,
        'preprocess': 'letterbox',
        'input': 'float32 [1,224,224,3], whole image letterboxed on grey 114, x/127.5-1',
        'trained_at': datetime.datetime.now().isoformat(timespec='seconds'),
        'source': os.path.abspath(sorted_dir),
    }
    target = out_dir if not install else install
    os.makedirs(target, exist_ok=True)
    with open(os.path.join(target, 'monument_classifier.tflite'), 'wb') as f:
        f.write(tflite)
    with open(os.path.join(target, 'monument_labels.txt'), 'w', encoding='utf8') as f:
        f.write(''.join(f'{i} {c}\n' for i, c in enumerate(classes)))
    with open(os.path.join(target, 'monument_model_info.json'), 'w', encoding='utf8') as f:
        json.dump(info, f, indent=2)
    print(f'\nWritten to {os.path.abspath(target)}. Rebuild the app: '
          'flutter build apk --release --split-per-abi')


if __name__ == '__main__':
    here = os.path.dirname(os.path.abspath(__file__))
    app = os.path.dirname(here)
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument('--photos', help='folder of unsorted photos (auto-sorted with YOLO first)')
    src.add_argument('--sorted', help='folder with one sub-folder per class name')
    src.add_argument('--labelled', help='folder with one sub-folder per denomination '
                     '(10, 20, …, 5000), fronts and backs mixed')
    ap.add_argument('--yolo', default=os.path.join(app, 'assets', 'models', 'yolo11s_currency.tflite'))
    ap.add_argument('--install', default=os.path.join(app, 'assets', 'models'),
                    help='where the app reads models from (default: assets/models)')
    ap.add_argument('--out', default=None, help='write here instead of installing')
    ap.add_argument('--min-per-class', type=int, default=15)
    ap.add_argument('--epochs', type=int, default=12)
    ap.add_argument('--seed', type=int, default=7)
    ap.add_argument('--sort-only', action='store_true', help='only auto-sort, do not train')
    a = ap.parse_args()

    if a.labelled:
        sorted_dir = sort_labelled(a.labelled, a.yolo)
    else:
        sorted_dir = a.sorted or auto_sort(a.photos, a.yolo)
    if a.sort_only:
        sys.exit(0)
    train(sorted_dir, a.out, None if a.out else a.install, a.min_per_class, a.epochs, a.seed)
