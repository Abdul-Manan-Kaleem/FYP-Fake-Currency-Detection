"""Builds the training set of the face-level Quaid-e-Azam portrait check.

Genuine class  : the real front photos (1,688 photos of 7 values), unchanged.
Tampered class : the same photos with the portrait changed, in four ways:
  A  the face is replaced by another person's photo (LFW public face data set)
  B  as A, plus an accessory: sunglasses, glasses, earrings, a nose pin
  C  the genuine portrait with an accessory drawn on it
  D  the genuine portrait with a smile or a sad mouth drawn on it, or the face blurred / covered

How the portrait is found in each photo: one upright reference photo per value has its face box marked by
hand (REF_FACE below, fractions of the photo). SIFT features match every other photo of that value to the
reference, a homography maps the face box into the photo, so the portrait is found whatever the rotation,
distance or tilt of the photo.

    python gen_dataset.py --photos DataSet_portrait --refs face_work --lfw lfw.npz --out DIR
"""
import argparse
import glob
import json
import os
import random

import cv2
import numpy as np
from PIL import Image, ImageOps

SIZE = 320
PAD = 114

# Face box (x0, y0, x1, y1) as fractions of the upright reference photo. Marked by hand on ref_<value>.png.
REF_FACE = {
    10: (0.46, 0.40, 0.62, 0.68),
    20: (0.70, 0.40, 0.86, 0.72),
    50: (0.08, 0.46, 0.34, 0.80),
    100: (0.50, 0.38, 0.68, 0.78),
    500: (0.51, 0.34, 0.69, 0.80),
    1000: (0.48, 0.30, 0.65, 0.72),
    5000: (0.03, 0.30, 0.30, 0.72),
}


def load_rgb(path, max_side=1000):
    im = ImageOps.exif_transpose(Image.open(path)).convert('RGB')
    im.thumbnail((max_side, max_side))
    return np.asarray(im)


def letterbox(img, size=SIZE):
    h, w = img.shape[:2]
    r = size / max(h, w)
    nw, nh = max(1, round(w * r)), max(1, round(h * r))
    small = cv2.resize(img, (nw, nh), interpolation=cv2.INTER_AREA)
    canvas = np.full((size, size, 3), PAD, np.uint8)
    y0, x0 = (size - nh) // 2, (size - nw) // 2
    canvas[y0:y0 + nh, x0:x0 + nw] = small
    return canvas


class Registrar:
    """Finds the face box of a photo by matching it to the reference photo of its value."""

    def __init__(self, refs_dir):
        self.sift = cv2.SIFT_create(nfeatures=2500)
        self.ref = {}
        for d, box in REF_FACE.items():
            im = load_rgb(os.path.join(refs_dir, f'ref_{d}.png'), 800)
            g = cv2.cvtColor(im, cv2.COLOR_RGB2GRAY)
            kp, de = self.sift.detectAndCompute(g, None)
            h, w = g.shape
            x0, y0, x1, y1 = box
            quad = np.float32([[x0 * w, y0 * h], [x1 * w, y0 * h], [x1 * w, y1 * h], [x0 * w, y1 * h]])
            self.ref[d] = (kp, de, quad)
        self.bf = cv2.BFMatcher()

    def face_quad(self, img, denom):
        kp0, de0, quad = self.ref[denom]
        g = cv2.cvtColor(img, cv2.COLOR_RGB2GRAY)
        kp, de = self.sift.detectAndCompute(g, None)
        if de is None or len(kp) < 30:
            return None
        pairs = self.bf.knnMatch(de0, de, k=2)
        good = [m for m, n in (p for p in pairs if len(p) == 2) if m.distance < 0.72 * n.distance]
        if len(good) < 25:
            return None
        src = np.float32([kp0[m.queryIdx].pt for m in good]).reshape(-1, 1, 2)
        dst = np.float32([kp[m.trainIdx].pt for m in good]).reshape(-1, 1, 2)
        H, mask = cv2.findHomography(src, dst, cv2.RANSAC, 5.0)
        if H is None or int(mask.sum()) < 20:
            return None
        q = cv2.perspectiveTransform(quad.reshape(-1, 1, 2), H).reshape(4, 2)
        h, w = img.shape[:2]
        # reject absurd geometry
        area = cv2.contourArea(q.astype(np.float32))
        if area < 0.004 * w * h or area > 0.5 * w * h or not cv2.isContourConvex(q.astype(np.float32)):
            return None
        return q.astype(np.float32)


def face_crop(face_img):
    """scikit-learn's LFW images (125 x 94) already show just the face; trim a little border."""
    h, w = face_img.shape[:2]
    return face_img[int(h * 0.04):int(h * 0.98), int(w * 0.04):int(w * 0.96)]


def tint_like(face, region, rng):
    """Make a photographed face look printed in the note's colours."""
    g = cv2.cvtColor(face, cv2.COLOR_RGB2GRAY).astype(np.float32)
    g = (g - g.min()) / max(1.0, g.max() - g.min())
    mean = region.reshape(-1, 3).mean(0).astype(np.float32)
    mode = rng.random()
    if mode < 0.7:                               # printed look: grey levels in the portrait's colour
        bright = rng.uniform(1.0, 1.5)
        out = g[..., None] * (mean * bright)[None, None, :]
        out = np.clip(out + rng.uniform(0, 40), 0, 255)
    else:                                        # natural colour, lowered saturation
        out = face.astype(np.float32)
        gray = g[..., None] * 255
        out = 0.5 * out + 0.5 * gray
    return out.astype(np.uint8)


def paste_quad(img, patch, quad, feather=0.35, alpha=0.95):
    h, w = img.shape[:2]
    ph, pw = patch.shape[:2]
    src = np.float32([[0, 0], [pw, 0], [pw, ph], [0, ph]])
    M = cv2.getPerspectiveTransform(src, quad.astype(np.float32))
    warped = cv2.warpPerspective(patch, M, (w, h), flags=cv2.INTER_LINEAR)
    mask = np.zeros((h, w), np.float32)
    # ellipse-like mask inside the quad
    c = quad.mean(0)
    ax = np.linalg.norm(quad[1] - quad[0]) / 2 * 0.95
    ay = np.linalg.norm(quad[3] - quad[0]) / 2 * 0.98
    ang = np.degrees(np.arctan2(*(quad[1] - quad[0])[::-1]))
    cv2.ellipse(mask, (int(c[0]), int(c[1])), (max(2, int(ax)), max(2, int(ay))), ang, 0, 360, 1.0, -1)
    k = max(3, int(min(ax, ay) * feather) | 1)
    mask = cv2.GaussianBlur(mask, (k, k), 0)[..., None] * alpha
    return (img * (1 - mask) + warped * mask).astype(np.uint8)


# ---- drawn accessories, positions as fractions inside the face quad (u across, v down) --------------------
def pt(quad, u, v):
    top = quad[0] + (quad[1] - quad[0]) * u
    bot = quad[3] + (quad[2] - quad[3]) * u
    return top + (bot - top) * v


def draw_accessory(img, quad, kind, rng):
    out = img.copy()
    w = np.linalg.norm(quad[1] - quad[0])
    h = np.linalg.norm(quad[3] - quad[0])
    s = max(2, int(round(min(w, h) / 22)))
    eye_v = rng.uniform(0.30, 0.40)
    if kind == 'sunglasses':
        for cu in (0.30, 0.70):
            c = pt(quad, cu, eye_v)
            axes = (int(w * 0.17), int(h * 0.09))
            col = (int(rng.integers(5, 50)),) * 3
            cv2.ellipse(out, (int(c[0]), int(c[1])), axes, 0, 0, 360, col, -1)
        a, b = pt(quad, 0.47, eye_v), pt(quad, 0.53, eye_v)
        cv2.line(out, tuple(map(int, a)), tuple(map(int, b)), (20, 20, 20), max(1, s))
        for u in (0.08, 0.92):
            cv2.line(out, tuple(map(int, pt(quad, u, eye_v))), tuple(map(int, pt(quad, u + (0.06 if u < 0.5 else -0.06), eye_v))), (20, 20, 20), max(1, s))
    elif kind == 'glasses':
        for cu in (0.30, 0.70):
            c = pt(quad, cu, eye_v)
            cv2.ellipse(out, (int(c[0]), int(c[1])), (int(w * 0.16), int(h * 0.085)), 0, 0, 360, (25, 25, 25), max(1, s))
        cv2.line(out, tuple(map(int, pt(quad, 0.46, eye_v))), tuple(map(int, pt(quad, 0.54, eye_v))), (25, 25, 25), max(1, s))
    elif kind == 'earring':
        for u in (0.0, 1.0):
            c = pt(quad, u, rng.uniform(0.55, 0.70))
            r = max(4, int(w * 0.10))
            cv2.circle(out, (int(c[0]), int(c[1])), r, (30, 170, 220), -1)
            cv2.circle(out, (int(c[0]), int(c[1])), r, (20, 20, 20), 2)
    elif kind == 'nosepin':
        c = pt(quad, rng.choice([0.40, 0.60]), rng.uniform(0.58, 0.64))
        cv2.circle(out, (int(c[0]), int(c[1])), max(3, int(w * 0.07)), (30, 190, 235), -1)
        cv2.circle(out, (int(c[0]), int(c[1])), max(3, int(w * 0.07)), (20, 20, 20), 1)
    elif kind == 'smile':
        pts = [pt(quad, 0.30 + 0.40 * t, 0.80 - 0.07 * np.sin(np.pi * t)) for t in np.linspace(0, 1, 12)]
        cv2.polylines(out, [np.int32(pts)], False, (30, 20, 60), max(1, s), cv2.LINE_AA)
    elif kind == 'sad':
        pts = [pt(quad, 0.30 + 0.40 * t, 0.80 + 0.06 * np.sin(np.pi * t)) for t in np.linspace(0, 1, 12)]
        cv2.polylines(out, [np.int32(pts)], False, (30, 20, 60), max(1, s), cv2.LINE_AA)
    elif kind == 'blur':
        m = np.zeros(img.shape[:2], np.uint8)
        cv2.fillConvexPoly(m, quad.astype(np.int32), 255)
        b = cv2.GaussianBlur(img, (0, 0), max(3, w * 0.12))
        out = np.where(m[..., None] > 0, b, out)
    elif kind == 'cover':
        m = np.zeros(img.shape[:2], np.uint8)
        cv2.fillConvexPoly(m, quad.astype(np.int32), 255)
        col = tuple(int(v) for v in rng.integers(0, 255, 3))
        out = np.where(m[..., None] > 0, np.array(col, np.uint8), out)
    return out


def degrade(img, rng):
    """Phone-photo look: same distribution for genuine and tampered samples."""
    if rng.random() < 0.5:
        img = np.clip(img.astype(np.float32) * rng.uniform(0.75, 1.25) + rng.uniform(-20, 20), 0, 255).astype(np.uint8)
    if rng.random() < 0.3:
        img = cv2.GaussianBlur(img, (0, 0), rng.uniform(0.5, 1.6))
    if rng.random() < 0.5:
        ok, enc = cv2.imencode('.jpg', img, [cv2.IMWRITE_JPEG_QUALITY, int(rng.integers(40, 92))])
        img = cv2.imdecode(enc, cv2.IMREAD_COLOR)
    return img


_REG = None


def _init_worker(refs_dir):
    global _REG
    _REG = Registrar(refs_dir)


def _find_quad(item):
    d, p = item
    try:
        return _REG.face_quad(load_rgb(p), d)
    except Exception:  # noqa: BLE001
        return None


def burst_key(path):
    import re
    n = os.path.basename(path)
    m = (re.search(r'(\d{8})_(\d{4})\d{2}', n) or re.search(r'(\d{4}-\d{2}-\d{2}) at (\d{2}\.\d{2})', n)
         or re.search(r'IMG(\d{8})(\d{4})', n))
    return '_'.join(m.groups()) if m else n


ACCESSORIES = ['sunglasses', 'glasses', 'earring', 'nosepin']
EXPR = ['smile', 'sad', 'blur', 'cover']


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--photos', required=True)
    ap.add_argument('--refs', required=True)
    ap.add_argument('--lfw', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--limit', type=int, default=0)
    a = ap.parse_args()
    rng = np.random.default_rng(7)
    random.seed(7)
    lfw = np.load(a.lfw)
    faces, who = lfw['images'], lfw['target']
    people = np.unique(who)
    rng.shuffle(people)
    test_people = set(people[: max(1, len(people) // 5)].tolist())      # held-out people for the test set
    tr_idx = [i for i, p in enumerate(who) if p not in test_people]
    te_idx = [i for i, p in enumerate(who) if p in test_people]
    print(f'faces: train {len(tr_idx)}  test (other people) {len(te_idx)}', flush=True)

    from multiprocessing import Pool
    os.makedirs(a.out, exist_ok=True)
    items = []
    for d in REF_FACE:
        for p in sorted(glob.glob(os.path.join(a.photos, f'portrait_{d}', '*'))):
            items.append((d, p))
    if a.limit:
        random.shuffle(items)
        items = items[: a.limit]
    # split by burst (same minute stays together)
    keys = sorted({burst_key(p) for _, p in items})
    random.shuffle(keys)
    test_keys = set(keys[: len(keys) // 5])

    # find the portrait in every photo (SIFT matching, in parallel)
    with Pool(4, initializer=_init_worker, initargs=(a.refs,)) as pool:
        quads = pool.map(_find_quad, items, chunksize=8)
    print(f'portrait found in {sum(q is not None for q in quads)} of {len(items)} photos', flush=True)

    X, Y, S, META = [], [], [], []
    skipped = 0
    for n, ((d, p), quad) in enumerate(zip(items, quads)):
        img = load_rgb(p)
        if quad is None:
            skipped += 1
            continue
        split = 1 if burst_key(p) in test_keys else 0                  # 1 = test
        pool = te_idx if split else tr_idx
        samples = [(img, 0, 'genuine')]
        # A: another person
        for kind in ('A', 'B', 'C', 'D'):
            if kind in ('A', 'B'):
                f = faces[int(rng.choice(pool))]
                f = face_crop(f)
                if rng.random() < 0.5:
                    f = f[:, ::-1]
                region = img[int(quad[:, 1].min()):int(quad[:, 1].max()), int(quad[:, 0].min()):int(quad[:, 0].max())]
                if region.size == 0:
                    continue
                f = tint_like(np.ascontiguousarray(f), region, rng)
                t = paste_quad(img, f, quad, alpha=float(rng.uniform(0.85, 1.0)))
                if kind == 'B':
                    t = draw_accessory(t, quad, rng.choice(ACCESSORIES), rng)
                samples.append((t, 1, kind))
            elif kind == 'C':
                samples.append((draw_accessory(img, quad, rng.choice(ACCESSORIES), rng), 1, 'C'))
            else:
                samples.append((draw_accessory(img, quad, rng.choice(EXPR), rng), 1, 'D'))
        for im, y, kind in samples:
            im = degrade(im, rng)
            X.append(letterbox(im))
            Y.append(y)
            S.append(split)
            META.append((os.path.basename(p), d, kind))
        if (n + 1) % 100 == 0:
            print(f'  {n + 1}/{len(items)} photos, {len(X)} samples, skipped {skipped}', flush=True)
    X = np.stack(X)
    np.savez(os.path.join(a.out, 'portrait_face_data.npz'), X=X, y=np.array(Y), split=np.array(S))
    json.dump(META, open(os.path.join(a.out, 'meta.json'), 'w'))
    print('done', X.shape, 'genuine', int((np.array(Y) == 0).sum()), 'tampered', int((np.array(Y) == 1).sum()),
          'skipped photos', skipped, flush=True)
    # a few examples to look at
    for i, (kind) in enumerate(('genuine', 'A', 'B', 'C', 'D')):
        idx = [j for j, m in enumerate(META) if m[2] == kind][:3]
        if idx:
            row = np.concatenate([X[j] for j in idx], 1)
            Image.fromarray(row).save(os.path.join(a.out, f'example_{kind}.png'))


if __name__ == '__main__':
    main()
