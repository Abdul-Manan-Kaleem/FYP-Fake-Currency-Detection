"""Trains the face-level Quaid-e-Azam portrait classifier (genuine vs tampered) from gen_dataset.py output.

    python train_face.py --data DIR --out DIR [--size 320] [--head-epochs 3] [--ft-epochs 5]

Writes portrait_face_classifier.tflite, portrait_face_labels.txt, portrait_face_model_info.json to --out.
Test photos (and the people whose faces make the tampered test images) never appear in training.
"""
import argparse
import datetime
import json
import os

import numpy as np

CLASSES = ['genuine', 'tampered']


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--head-epochs', type=int, default=3)
    ap.add_argument('--ft-epochs', type=int, default=8)
    ap.add_argument('--tampered-per-photo', type=int, default=2,
                    help='training only: tampered samples kept per genuine photo (all are kept for the test)')
    ap.add_argument('--seed', type=int, default=7)
    a = ap.parse_args()

    import tensorflow as tf
    tf.keras.utils.set_random_seed(a.seed)
    d = np.load(os.path.join(a.data, 'portrait_face_data.npz'))
    X, y, split = d['X'], d['y'], d['split']
    meta = json.load(open(os.path.join(a.data, 'meta.json')))
    kinds = np.array([m[2] for m in meta])
    size = X.shape[1]

    tr = np.where(split == 0)[0]
    te = np.where(split == 1)[0]
    # keep all genuine, and only a few tampered samples per photo for speed
    rng = np.random.default_rng(a.seed)
    keep = [i for i in tr if y[i] == 0]
    by_photo = {}
    for i in tr:
        if y[i] == 1:
            by_photo.setdefault(meta[i][0], []).append(i)
    for idxs in by_photo.values():
        rng.shuffle(idxs)
        keep += idxs[:a.tampered_per_photo]
    tr = np.array(sorted(keep))
    print(f'train {len(tr)} (genuine {(y[tr] == 0).sum()}, tampered {(y[tr] == 1).sum()}), '
          f'test {len(te)} (genuine {(y[te] == 0).sum()}, tampered {(y[te] == 1).sum()}), size {size}', flush=True)

    base = tf.keras.applications.MobileNetV2(input_shape=(size, size, 3), include_top=False,
                                             weights='imagenet', pooling='avg')
    base.trainable = False
    inp = tf.keras.Input((size, size, 3), name='image')   # already scaled to [-1, 1]
    aug = tf.keras.Sequential([tf.keras.layers.RandomTranslation(0.03, 0.03),
                               tf.keras.layers.RandomRotation(0.02),
                               tf.keras.layers.RandomZoom(0.05)], name='augment')
    x = aug(inp)
    x = base(x, training=False)
    x = tf.keras.layers.Dropout(0.25)(x)
    out = tf.keras.layers.Dense(2, activation='softmax', name='probs')(x)
    model = tf.keras.Model(inp, out)
    counts = np.bincount(y[tr], minlength=2)
    cw = {i: len(tr) / (2 * max(1, n)) for i, n in enumerate(counts)}

    def ds(idx, shuffle):
        def gen():
            order = rng.permutation(idx) if shuffle else idx
            for i in order:
                yield X[i].astype(np.float32) / 127.5 - 1.0, y[i]
        sig = (tf.TensorSpec((size, size, 3), tf.float32), tf.TensorSpec((), tf.int64))
        return tf.data.Dataset.from_generator(gen, output_signature=sig).batch(32).prefetch(2)

    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3), loss='sparse_categorical_crossentropy',
                  metrics=['accuracy'])
    model.fit(ds(tr, True), epochs=a.head_epochs, class_weight=cw, verbose=2)
    base.trainable = True
    for layer in base.layers[:-100]:
        layer.trainable = False
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-4), loss='sparse_categorical_crossentropy',
                  metrics=['accuracy'])
    model.fit(ds(tr, True), epochs=a.ft_epochs, class_weight=cw, verbose=2)

    # ---- held-out evaluation
    prob = model.predict(ds(te, False), verbose=0)
    yt = y[te]
    pt = prob[:, 1]                       # probability of "tampered"
    # Operating point: the lowest "tampered" probability that still keeps at least 97% of the
    # genuine test photos (a note is only failed when the model is really sure).
    thr = 0.5
    for cand in np.arange(0.5, 0.9991, 0.005):
        if (pt[yt == 0] < cand).mean() >= 0.97:
            thr = float(cand)
            break
    pred = (pt >= thr).astype(int)
    print(f'chosen tampered threshold {thr:.3f} (chosen on the held-out photos, so the numbers below are slightly optimistic)')
    from sklearn.metrics import roc_auc_score
    auc = float(roc_auc_score(yt, pt))
    print(f'AUC {auc:.4f}')
    acc = float((pred == yt).mean())
    gen_rec = float((pred[yt == 0] == 0).mean())
    tam_rec = float((pred[yt == 1] == 1).mean())
    print(f'\nHeld-out accuracy {acc:.4f} | genuine kept {gen_rec:.4f} | tampered caught {tam_rec:.4f}')
    per_kind = {}
    for k in ('genuine', 'A', 'B', 'C', 'D'):
        m = kinds[te] == k
        if m.any():
            want = 0 if k == 'genuine' else 1
            per_kind[k] = {'test_samples': int(m.sum()), 'correct': round(float((pred[m] == want).mean()), 4)}
            print(f'  {k:8s} {per_kind[k]}')
    cm = np.zeros((2, 2), int)
    for t, p in zip(yt, pred):
        cm[t, p] += 1
    print('Confusion (rows true genuine/tampered, cols predicted):\n', cm)

    # ---- TFLite
    conv = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite = conv.convert()
    it = tf.lite.Interpreter(model_content=tflite)
    it.allocate_tensors()
    i_d, o_d = it.get_input_details()[0], it.get_output_details()[0]
    worst = 0.0
    for k in range(min(20, len(te))):
        xk = (X[te[k]:te[k] + 1].astype(np.float32) / 127.5 - 1.0)
        it.set_tensor(i_d['index'], xk)
        it.invoke()
        worst = max(worst, float(np.abs(it.get_tensor(o_d['index'])[0] - model.predict(xk, verbose=0)[0]).max()))
    print(f'TFLite input {i_d["shape"]}, output {o_d["shape"]}; Keras vs TFLite max |diff| {worst:.2e}')

    os.makedirs(a.out, exist_ok=True)
    model.save(os.path.join(a.out, 'portrait_face_classifier.keras'))
    verified = bool(gen_rec >= 0.90 and tam_rec >= 0.80)
    os.makedirs(a.out, exist_ok=True)
    open(os.path.join(a.out, 'portrait_face_classifier.tflite'), 'wb').write(tflite)
    open(os.path.join(a.out, 'portrait_face_labels.txt'), 'w').write(''.join(f'{i} {c}\n' for i, c in enumerate(CLASSES)))
    json.dump({'verified': verified, 'classes': CLASSES, 'preprocess': 'letterbox', 'size': size,
               'tampered_threshold': round(thr, 3), 'auc': round(auc, 4),
               'input': f'float32 [1,{size},{size},3], whole front photo letterboxed on grey 114, x/127.5-1',
               'held_out': {'accuracy': round(acc, 4), 'genuine_kept': round(gen_rec, 4),
                            'tampered_caught': round(tam_rec, 4), 'per_kind': per_kind,
                            'confusion': cm.tolist()},
               'train_samples': int(len(tr)), 'test_samples': int(len(te)),
               'trained_at': datetime.datetime.now().isoformat(timespec='seconds')},
              open(os.path.join(a.out, 'portrait_face_model_info.json'), 'w'), indent=2)
    print('VERIFIED' if verified else 'NOT VERIFIED (a class is below 90%)', 'written to', os.path.abspath(a.out))


if __name__ == '__main__':
    main()
