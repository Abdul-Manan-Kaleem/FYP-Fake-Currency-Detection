"""10-fold cross-validation of the Rs 5,000 genuine / altered classifier (MobileNetV3-Large).

Genuine class = the real Rs 5,000 photos in DataSet/5000.
Altered class = the same photos with one localised alteration (blur, noise, brightness,
contrast, colour shift, texture noise or partial obstruction in one of the 32 patches),
generated with the notebook's own alteration functions (tools/cv/alter_funcs.py).
A photo and its altered copy always sit in the same fold, so the classifier never sees
the original of a test image during training.

Model: torchvision mobilenet_v3_large (ImageNet weights), last layer replaced by 2 outputs,
224 x 224 input resized directly, ImageNet mean/std, AdamW 5e-4, 8 epochs; one fold group per photo, batch 32.

    python cv_rs5000.py --data "C:\\...\\DataSet\\5000" --out report.json
"""
import argparse
import json
import os
import random
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import cv_common as cc


def build_images(folder, size=112, max_side=1024):
    """Return (X uint8 [N,3,224,224], y, group, names). Photo i -> rows 2i (genuine), 2i+1 (altered)."""
    import cv2
    import alter_funcs as af
    files = sorted(os.path.join(dp, f) for dp, _, fs in os.walk(folder) for f in fs
                   if f.lower().endswith(cc.IMG_EXT))
    xs, ys, gs, names = [], [], [], []
    for i, p in enumerate(files):
        im = cv2.imread(p)
        if im is None:
            continue
        im = cv2.cvtColor(im, cv2.COLOR_BGR2RGB)
        h, w = im.shape[:2]
        if h < 150 or w < 150:
            continue
        s = max_side / max(h, w)
        if s < 1:
            im = cv2.resize(im, (int(w * s), int(h * s)), interpolation=cv2.INTER_AREA)
        random.seed(cc.SEED + i)
        np.random.seed(cc.SEED + i)
        pidx = random.randint(0, af.GRID_COLS * af.GRID_ROWS - 1)
        box = af.get_patch_region(im, pidx)
        name = random.choice(list(af.ALTERATIONS))
        alt = af.ALTERATIONS[name](im, box)
        # One sample = one cell of the notebook's 8 x 4 patch grid (the cell that was altered):
        # genuine cell vs the same cell after the alteration. A whole-photo view at 224 px
        # shows the alteration in under 1% of pixels, which no classifier can see.
        sx1, sy1, sx2, sy2 = af.get_safe_area(im)
        pw, ph = (sx2 - sx1) / af.GRID_COLS, (sy2 - sy1) / af.GRID_ROWS
        cx1 = int(sx1 + (pidx % af.GRID_COLS) * pw)
        cy1 = int(sy1 + (pidx // af.GRID_COLS) * ph)
        crop = (cy1, int(cy1 + ph), cx1, int(cx1 + pw))
        for img, lab in ((im, 0), (alt, 1)):
            img = img[crop[0]:crop[1], crop[2]:crop[3]]
            r = cv2.resize(img, (size, size), interpolation=cv2.INTER_AREA)
            xs.append(r.transpose(2, 0, 1))
            ys.append(lab)
            gs.append(cc.source_stem(p))
            names.append(os.path.basename(p) + ('' if lab == 0 else '|' + name))
        if (i + 1) % 100 == 0:
            print(f'  prepared {i + 1}/{len(files)}', flush=True)
    return np.stack(xs), np.array(ys), gs, names


def run_fold(x, y, tr, te, seed, epochs=5, batch=32):
    import torch
    import torch.nn as nn
    from torchvision.models import mobilenet_v3_large, MobileNet_V3_Large_Weights
    torch.manual_seed(seed)
    torch.set_num_threads(4)
    model = mobilenet_v3_large(weights=MobileNet_V3_Large_Weights.IMAGENET1K_V1)
    model.classifier[-1] = nn.Linear(model.classifier[-1].in_features, 2)
    mean = torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1)
    std = torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1)

    def prep(idx):
        t = torch.from_numpy(x[idx]).float() / 255.0
        return (t - mean) / std

    opt = torch.optim.AdamW(model.parameters(), lr=5e-4, weight_decay=1e-4)
    loss_fn = nn.CrossEntropyLoss()
    rng = np.random.RandomState(seed)
    for ep in range(epochs):
        model.train()
        order = rng.permutation(tr)
        total = 0.0
        for i in range(0, len(order), batch):
            b = order[i:i + batch]
            if len(b) < 2:
                continue
            opt.zero_grad()
            loss = loss_fn(model(prep(b)), torch.from_numpy(y[b]).long())
            loss.backward()
            opt.step()
            total += float(loss) * len(b)
        print(f'    epoch {ep + 1}/{epochs} loss {total / len(order):.4f}', flush=True)
    model.eval()
    probs = []
    with torch.inference_mode():
        for i in range(0, len(te), 64):
            b = te[i:i + 64]
            probs.append(torch.softmax(model(prep(b)), 1)[:, 1].numpy())
    return np.concatenate(probs)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--folds', type=int, default=10)
    ap.add_argument('--epochs', type=int, default=8)
    a = ap.parse_args()

    x, y, groups, names = build_images(a.data)
    n_src = len(y) // 2
    print(f'{n_src} genuine photos + {n_src} altered copies, {len(set(groups))} bursts', flush=True)
    # fold on the source photos, then expand each photo to its two rows
    src_groups = groups[0::2]
    src_labels = np.zeros(n_src, dtype=int)
    folds = cc.make_folds(src_groups, src_labels, a.folds)
    partial = a.out + '.partial'      # finished folds are kept, so a stopped run resumes
    results = json.load(open(partial, encoding='utf8')) if os.path.exists(partial) else []
    for k, (tr_s, te_s) in enumerate(folds, 1):
        if any(r['fold'] == k for r in results):
            print(f'Fold {k}: already done, skipped', flush=True)
            continue
        expand = lambda s: np.sort(np.concatenate([2 * s, 2 * s + 1]))
        tr, te = expand(tr_s), expand(te_s)
        print(f'Fold {k}/{a.folds}: {len(tr)} training images, {len(te)} test images', flush=True)
        prob = run_fold(x, y, tr, te, cc.SEED + k, a.epochs)
        r = cc.binary_metrics(y[te], prob)
        r.update(fold=k, train_photos=int(len(tr)))
        results.append(r)
        json.dump(results, open(partial, 'w', encoding='utf8'))
        print(f'Fold {k}: acc {r["accuracy"]:.4f} prec {r["precision"]:.4f} rec {r["recall"]:.4f} '
              f'f1 {r["f1"]:.4f} auc {r["auc"]:.4f}', flush=True)
    summary = cc.summarise(results, ['accuracy', 'precision', 'recall', 'f1', 'auc'])
    print('Summary', summary, flush=True)
    cc.save_report(a.out, dict(model='MobileNetV3-Large Rs 5000 genuine/altered',
                               task='binary classification', classes=['genuine', 'altered'],
                               source=a.data, genuine_photos=n_src, altered_images=n_src,
                               bursts=len(set(groups)), epochs=a.epochs, folds=results,
                               summary=summary))


if __name__ == '__main__':
    main()

