"""Shared helpers for the 10-fold cross-validation scripts.

Every model uses the same fold rules so the numbers can be compared:

* Roboflow writes several augmented copies of one photo (names contain '.rf.').
  Only one copy per source photo is kept.
* Photos taken within the same minute (a burst of the same note) are kept
  together, so near-identical photos never sit in both the training and the
  test part of a fold.
* Folds are stratified (each fold has about the same class mix), shuffled with
  a fixed seed (7) and are therefore repeatable.
"""
import json
import os
import re
import time

import numpy as np

SEED = 7
IMG_EXT = ('.jpg', '.jpeg', '.png', '.bmp', '.webp')


def source_stem(name):
    """File name without the Roboflow augmentation suffix."""
    base = os.path.splitext(os.path.basename(name))[0]
    return base.split('.rf.')[0]


def burst_key(name):
    """Photos of the same minute share one key (camera / WhatsApp time stamps)."""
    s = source_stem(name)
    m = re.search(r'(\d{8})[_-]?(\d{4})\d{2}', s)             # 20260812_161846, IMG20220209121614
    if m:
        return f'{m.group(1)}_{m.group(2)}'
    m = re.search(r'(\d{4}-\d{2}-\d{2}) at (\d{2})\.(\d{2})', s)   # WhatsApp Image 2026-08-09 at 07.18.50
    if m:
        return f'{m.group(1)}_{m.group(2)}{m.group(3)}'
    return s


def make_folds(groups, labels, k=10, seed=SEED):
    """Return a list of (train_idx, test_idx). `groups` keep bursts together."""
    from sklearn.model_selection import StratifiedGroupKFold
    sgkf = StratifiedGroupKFold(n_splits=k, shuffle=True, random_state=seed)
    idx = np.arange(len(labels))
    return [(tr, te) for tr, te in sgkf.split(idx, labels, groups)]


def binary_metrics(y_true, prob, thr=0.5):
    """Accuracy, precision, recall, F1, AUC and confusion counts (positive class = 1)."""
    from sklearn.metrics import roc_auc_score
    y_true = np.asarray(y_true)
    pred = (np.asarray(prob) >= thr).astype(int)
    tp = int(((pred == 1) & (y_true == 1)).sum())
    tn = int(((pred == 0) & (y_true == 0)).sum())
    fp = int(((pred == 1) & (y_true == 0)).sum())
    fn = int(((pred == 0) & (y_true == 1)).sum())
    acc = (tp + tn) / max(1, len(y_true))
    prec = tp / max(1, tp + fp)
    rec = tp / max(1, tp + fn)
    f1 = 2 * prec * rec / max(1e-9, prec + rec)
    try:
        auc = float(roc_auc_score(y_true, prob))
    except ValueError:
        auc = float('nan')
    return dict(accuracy=round(acc, 4), precision=round(prec, 4), recall=round(rec, 4),
                f1=round(f1, 4), auc=round(auc, 4), tp=tp, tn=tn, fp=fp, fn=fn,
                test_photos=int(len(y_true)))


def summarise(folds, keys):
    out = {}
    for k in keys:
        v = np.array([f[k] for f in folds], dtype=float)
        out[k] = dict(mean=round(float(np.nanmean(v)), 4), std=round(float(np.nanstd(v)), 4),
                      min=round(float(np.nanmin(v)), 4), max=round(float(np.nanmax(v)), 4))
    return out


def save_report(path, report):
    report['run_at'] = time.strftime('%Y-%m-%dT%H:%M:%S')
    with open(path, 'w', encoding='utf8') as f:
        json.dump(report, f, indent=2)
    print('Report written to', path, flush=True)
