"""10-fold cross-validation of the YOLO11s note detector.

Data: a Roboflow export in YOLOv4-PyTorch format (one `_annotations.txt` per split with
`file x1,y1,x2,y2,class ...`). Only one copy of each source photo is kept and photos from
the same minute stay in one fold (see cv_common.py).

Each fold trains a fresh YOLO11s (COCO weights) on the other nine folds and measures
precision, recall, mAP50 and mAP50-95 on the held-out fold.

The training budget is far smaller than the app model's (100 epochs, 640 px, GPU), because
this runs on a CPU: see --imgsz, --epochs and --max-train. The numbers are therefore a
lower bound of what the full training reaches.

    python cv_yolo.py --data "E:\\...\\LargeDataset.v4i.yolov4pytorch" --work work_dir --out report.json
"""
import argparse
import os
import shutil
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import cv_common as cc


def load_sources(root, keep_classes):
    """One entry per source photo: (path, [(x1,y1,x2,y2,cls)], primary class)."""
    classes = [l.strip() for l in open(os.path.join(root, 'train', '_classes.txt'), encoding='utf8') if l.strip()]
    keep = {i: j for j, i in enumerate(i for i, n in enumerate(classes) if n in keep_classes)}
    names = [classes[i] for i in keep]
    chosen = {}
    for split in ('test', 'valid', 'train'):        # prefer un-augmented copies
        ann = os.path.join(root, split, '_annotations.txt')
        for line in open(ann, encoding='utf8'):
            p = line.split()
            if not p:
                continue
            stem = cc.source_stem(p[0])
            if stem in chosen:
                continue
            boxes = []
            for b in p[1:]:
                x1, y1, x2, y2, c = (int(float(v)) for v in b.split(','))
                if c in keep:
                    boxes.append((x1, y1, x2, y2, keep[c]))
            path = os.path.join(root, split, p[0])
            if boxes and os.path.exists(path):
                chosen[stem] = (path, boxes, boxes[0][4])
    return names, list(chosen.values())


def write_dataset(items, work, imgsz):
    """Resize every photo once (long side = imgsz) and write YOLO label files."""
    from PIL import Image
    img_dir, lab_dir = os.path.join(work, 'images'), os.path.join(work, 'labels')
    os.makedirs(img_dir, exist_ok=True)
    os.makedirs(lab_dir, exist_ok=True)
    out = []
    for i, (path, boxes, _) in enumerate(items):
        stem = f'{i:05d}'
        im = Image.open(path).convert('RGB')
        w, h = im.size
        s = imgsz / max(w, h)
        if s < 1:
            im = im.resize((max(1, int(w * s)), max(1, int(h * s))), Image.BILINEAR)
        im.save(os.path.join(img_dir, stem + '.jpg'), quality=92)
        with open(os.path.join(lab_dir, stem + '.txt'), 'w') as f:
            for x1, y1, x2, y2, c in boxes:
                x1, x2 = max(0, min(x1, x2)), min(w, max(x1, x2))
                y1, y2 = max(0, min(y1, y2)), min(h, max(y1, y2))
                if x2 - x1 < 2 or y2 - y1 < 2:
                    continue
                f.write(f'{c} {(x1 + x2) / 2 / w:.6f} {(y1 + y2) / 2 / h:.6f} '
                        f'{(x2 - x1) / w:.6f} {(y2 - y1) / h:.6f}\n')
        out.append(os.path.join(img_dir, stem + '.jpg'))
        if (i + 1) % 500 == 0:
            print(f'  prepared {i + 1}/{len(items)}', flush=True)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True)
    ap.add_argument('--work', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--folds', type=int, default=10)
    ap.add_argument('--imgsz', type=int, default=320)
    ap.add_argument('--epochs', type=int, default=5)
    ap.add_argument('--max-train', type=int, default=0, help='cap training photos per fold (0 = all)')
    ap.add_argument('--weights', default='yolo11s.pt')
    ap.add_argument('--only-fold', type=int, default=0)
    a = ap.parse_args()

    wanted = {'1000Rupees', '100Rupees', '10Rupees', '20Rupees', '5000Rupees', '500Rupees', '50Rupees'}
    names, items = load_sources(a.data, wanted)
    print(f'{len(items)} source photos, classes {names}', flush=True)
    os.makedirs(a.work, exist_ok=True)
    paths = write_dataset(items, a.work, a.imgsz)
    primary = np.array([it[2] for it in items])
    groups = [cc.burst_key(it[0]) for it in items]
    folds = cc.make_folds(groups, primary, a.folds)

    from ultralytics import YOLO
    import json
    # folds finished earlier are read back from the report, so a stopped run resumes
    results = json.load(open(a.out, encoding='utf8'))['folds'] if os.path.exists(a.out) else []
    for k, (tr, te) in enumerate(folds, 1):
        if a.only_fold and k != a.only_fold:
            continue
        if any(r['fold'] == k for r in results):
            print(f'Fold {k}: already done, skipped', flush=True)
            continue
        rng = np.random.RandomState(cc.SEED + k)
        tr_use = rng.permutation(tr)[:a.max_train] if a.max_train else tr
        tl = os.path.join(a.work, f'fold{k}_train.txt')
        vl = os.path.join(a.work, f'fold{k}_test.txt')
        open(tl, 'w').write('\n'.join(paths[i] for i in tr_use))
        open(vl, 'w').write('\n'.join(paths[i] for i in te))
        yaml = os.path.join(a.work, f'fold{k}.yaml')
        open(yaml, 'w').write(f'train: {tl}\nval: {vl}\nnc: {len(names)}\nnames: {names}\n')
        print(f'Fold {k}/{a.folds}: {len(tr_use)} training photos, {len(te)} test photos', flush=True)
        model = YOLO(a.weights)
        model.train(data=yaml, epochs=a.epochs, imgsz=a.imgsz, batch=16, workers=2, seed=cc.SEED + k,
                    device='cpu', project=os.path.join(a.work, 'runs'), name=f'fold{k}', exist_ok=True,
                    plots=False, verbose=False, patience=a.epochs, optimizer='AdamW', lr0=0.001,
                    cos_lr=True, val=False)
        m = model.val(data=yaml, imgsz=a.imgsz, batch=16, device='cpu', plots=False, verbose=False).box
        per_class = {}
        try:
            for j, ci in enumerate(m.ap_class_index):
                per_class[names[int(ci)]] = round(float(m.ap50[j]), 4)
        except Exception:  # noqa: BLE001
            pass
        r = dict(fold=k, train_photos=int(len(tr_use)), test_photos=int(len(te)),
                 precision=round(float(m.mp), 4), recall=round(float(m.mr), 4),
                 map50=round(float(m.map50), 4), map50_95=round(float(m.map), 4), per_class_map50=per_class)
        results.append(r)
        print(f'Fold {k}: P {r["precision"]:.4f} R {r["recall"]:.4f} mAP50 {r["map50"]:.4f} '
              f'mAP50-95 {r["map50_95"]:.4f}', flush=True)
        shutil.rmtree(os.path.join(a.work, 'runs', f'fold{k}'), ignore_errors=True)
        cc.save_report(a.out, dict(model='YOLO11s denomination detector', task='object detection',
                                   classes=names, source=a.data, photos=len(items), imgsz=a.imgsz,
                                   epochs=a.epochs, max_train=a.max_train, folds=results,
                                   summary=cc.summarise(results, ['precision', 'recall', 'map50', 'map50_95'])))


if __name__ == '__main__':
    main()
