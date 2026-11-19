"""10-fold cross-validation of the MobileNetV3-Small genuine / fake classifier.

Matches the model in the app: MobileNetV3Small (ImageNet weights, include_preprocessing=True),
backbone frozen, head = Dropout(0.30) + Dense(1, sigmoid) = fake_probability, Adam 1e-3,
balanced class weights, early stopping on a validation part of the training folds,
threshold 0.50, 224 x 224 input resized directly.

To keep the run affordable on a CPU the frozen backbone is run once per photo and the
head is trained on those stored features (the same maths, because the backbone never
changes). The notebook's light random rotation / zoom augmentation is not applied.

    python cv_mnv3small.py --data "E:\\FYP\\DATA-SET\\Fake Currency Detection.v2i.multiclass" --out report.json
"""
import argparse
import csv
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import cv_common as cc


def load_dataset(root):
    """(path, label) with label 0 = genuine, 1 = fake; one copy per source photo."""
    seen, rows = {}, []
    for split in ('test', 'valid', 'train'):          # prefer the un-augmented copies
        csv_path = os.path.join(root, split, '_classes.csv')
        if not os.path.exists(csv_path):
            continue
        with open(csv_path, newline='', encoding='utf8') as f:
            for r in csv.DictReader(f):
                r = {k.strip(): v for k, v in r.items()}
                name = r['filename']
                stem = cc.source_stem(name)
                if stem in seen:
                    continue
                seen[stem] = 1
                label = 1 if int(r['fake']) == 1 else 0
                rows.append((os.path.join(root, split, name), label))
    return rows


def extract_features(paths, batch=64):
    import tensorflow as tf
    from PIL import Image
    base = tf.keras.applications.MobileNetV3Small(
        input_shape=(224, 224, 3), include_top=False, weights='imagenet',
        include_preprocessing=True, pooling='avg')
    feats = []
    for i in range(0, len(paths), batch):
        arr = []
        for p in paths[i:i + batch]:
            im = Image.open(p).convert('RGB').resize((224, 224), Image.BILINEAR)
            arr.append(np.asarray(im, dtype=np.float32))
        feats.append(base.predict(np.stack(arr), verbose=0))
        print(f'  features {min(i + batch, len(paths))}/{len(paths)}', flush=True)
    return np.concatenate(feats)


def train_head(x_tr, y_tr, x_va, y_va, seed):
    import tensorflow as tf
    from tensorflow.keras import layers
    tf.keras.utils.set_random_seed(seed)
    m = tf.keras.Sequential([layers.Input(shape=(x_tr.shape[1],)), layers.Dropout(0.30),
                             layers.Dense(1, activation='sigmoid')])
    m.compile(optimizer=tf.keras.optimizers.Adam(1e-3), loss='binary_crossentropy')
    n0, n1 = (y_tr == 0).sum(), (y_tr == 1).sum()
    cw = {0: len(y_tr) / (2 * max(1, n0)), 1: len(y_tr) / (2 * max(1, n1))}
    cb = [tf.keras.callbacks.EarlyStopping(monitor='val_loss', patience=6, restore_best_weights=True),
          tf.keras.callbacks.ReduceLROnPlateau(monitor='val_loss', factor=0.3, patience=2, min_lr=1e-6)]
    m.fit(x_tr, y_tr, validation_data=(x_va, y_va), epochs=60, batch_size=32,
          class_weight=cw, callbacks=cb, verbose=0)
    return m


def synthetic_features(dataset, denoms):
    """PROXY when the real Genuine/Fake folders are missing: genuine photos of `denoms`
    versus the same photos with one localised alteration (see cv_rs5000.py)."""
    import tensorflow as tf
    import cv_rs5000 as r5
    xs, ys, gs = [], [], []
    for d in denoms:
        x, y, g, _ = r5.build_images(os.path.join(dataset, d))
        xs.append(x), ys.append(y), gs.append(g)
    x = np.concatenate(xs).transpose(0, 2, 3, 1).astype(np.float32)
    base = tf.keras.applications.MobileNetV3Small(
        input_shape=(224, 224, 3), include_top=False, weights='imagenet',
        include_preprocessing=True, pooling='avg')
    feats = np.concatenate([base.predict(tf.image.resize(x[i:i + 64], (224, 224)).numpy(), verbose=0)
                            for i in range(0, len(x), 64)])
    return feats, np.concatenate(ys), [g for gl in gs for g in gl]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--folds', type=int, default=10)
    ap.add_argument('--synthetic', action='store_true',
                    help='--data is the DataSet folder; use genuine vs synthetically altered photos '
                         'of Rs 10-1000 as a stand-in for the missing Genuine/Fake folders')
    a = ap.parse_args()

    if a.synthetic:
        x, y, groups = synthetic_features(a.data, ['10', '20', '50', '100', '500', '1000'])
        n_src = len(y) // 2
        print(f'{n_src} genuine photos + {n_src} altered copies', flush=True)
        # a photo and its altered copy are adjacent rows and must share a fold
        sg = [groups[i] for i in range(0, len(y), 2)]
        src_folds = cc.make_folds(sg, np.zeros(n_src, dtype=int), a.folds)
        folds = [(np.sort(np.concatenate([2 * tr, 2 * tr + 1])), np.sort(np.concatenate([2 * te, 2 * te + 1])))
                 for tr, te in src_folds]
        rows = [None] * len(y)
    else:
        rows = load_dataset(a.data)
        paths = [p for p, _ in rows]
        y = np.array([l for _, l in rows])
        groups = [cc.burst_key(p) for p in paths]
        print(f'{len(rows)} source photos: genuine {(y == 0).sum()}, fake {(y == 1).sum()}, '
              f'{len(set(groups))} bursts', flush=True)
        x = extract_features(paths)
        folds = cc.make_folds(groups, y, a.folds)
    results = []
    for k, (tr, te) in enumerate(folds, 1):
        # 15 % of the training photos (whole bursts) are held back for early stopping
        sub = cc.make_folds([groups[i] for i in tr], y[tr], 7, seed=k)
        tr_in, va_in = sub[0]
        m = train_head(x[tr[tr_in]], y[tr[tr_in]], x[tr[va_in]], y[tr[va_in]], cc.SEED + k)
        prob = m.predict(x[te], verbose=0).ravel()
        r = cc.binary_metrics(y[te], prob)
        r.update(fold=k, train_photos=int(len(tr)))
        results.append(r)
        print(f'Fold {k}: acc {r["accuracy"]:.4f} prec {r["precision"]:.4f} rec {r["recall"]:.4f} '
              f'f1 {r["f1"]:.4f} auc {r["auc"]:.4f}  ({r["test_photos"]} test photos)', flush=True)
    summary = cc.summarise(results, ['accuracy', 'precision', 'recall', 'f1', 'auc'])
    print('Summary', summary, flush=True)
    cc.save_report(a.out, dict(model='MobileNetV3-Small genuine/fake'
                                     + (' (PROXY: genuine vs synthetically altered)' if a.synthetic else ''),
                               task='binary classification',
                               classes=['genuine', 'fake'], source=a.data, photos=len(rows),
                               genuine=int((y == 0).sum()), fake=int((y == 1).sum()),
                               bursts=len(set(groups)), folds=results, summary=summary))


if __name__ == '__main__':
    main()
