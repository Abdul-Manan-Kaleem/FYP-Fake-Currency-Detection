"""Parity check for checklist item 17: same image through .pt, TFLite (Python)
and the Flutter app, compared side by side.

Usage (Colab or local):
    pip install tensorflow pillow numpy            # + ultralytics for --pt
    python yolo_parity.py front.jpg --tflite yolo11s_currency.tflite [--pt best.pt]

The TFLite path below mirrors the app exactly
(lib/features/verification/data/on_device/image_preprocessor.dart and
yolo_decoder.dart): EXIF-corrected RGB, long side capped at 2048, letterbox
to 640 with grey 114 padding, /255, channels-first, then
conf 0.25 / IoU 0.7 class-aware NMS. Boxes are printed in the coordinates of
the 2048-capped working image, in the same "id:label score [x1, y1, x2, y2]"
format the app logs (`flutter run` → "YOLO front ...").
"""
import argparse
import json
import zipfile

import numpy as np
from PIL import Image, ImageOps

WORKING_LONG_SIDE = 2048
SIZE = 640
CONF, IOU = 0.25, 0.7


def names_from_tflite(path):
    with zipfile.ZipFile(path) as z:
        meta = json.loads(z.read("metadata.json"))
    return {int(k): v for k, v in meta["names"].items()}


def working_image(path):
    im = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    long = max(im.size)
    if long > WORKING_LONG_SIDE:
        r = WORKING_LONG_SIDE / long
        im = im.resize((round(im.width * r), round(im.height * r)), Image.BOX)
    return im


def letterbox(im):
    r = min(SIZE / im.width, SIZE / im.height)
    nw, nh = round(im.width * r), round(im.height * r)
    pad_x, pad_y = (SIZE - nw) // 2, (SIZE - nh) // 2
    canvas = Image.new("RGB", (SIZE, SIZE), (114, 114, 114))
    canvas.paste(im.resize((nw, nh), Image.BILINEAR), (pad_x, pad_y))
    x = np.asarray(canvas, dtype=np.float32) / 255.0  # HWC
    return x.transpose(2, 0, 1)[None], r, pad_x, pad_y  # BCHW


def iou(a, b):
    w = min(a[2], b[2]) - max(a[0], b[0])
    h = min(a[3], b[3]) - max(a[1], b[1])
    if w <= 0 or h <= 0:
        return 0.0
    inter = w * h
    area = lambda r: (r[2] - r[0]) * (r[3] - r[1])
    return inter / (area(a) + area(b) - inter)


def decode(out, normalized):
    out = out[0]  # (17, 8400)
    nc = out.shape[0] - 4
    scale = SIZE if normalized else 1.0
    scores = out[4:]
    cls = scores.argmax(0)
    best = scores.max(0)
    keep = best > CONF
    dets = []
    for a in np.nonzero(keep)[0]:
        cx, cy, w, h = out[:4, a] * scale
        dets.append((int(cls[a]), float(best[a]), [cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2]))
    dets.sort(key=lambda d: -d[1])
    kept = []
    for d in dets:
        if all(k[0] != d[0] or iou(k[2], d[2]) <= IOU for k in kept):
            kept.append(d)
    return kept[:300], nc


def run_tflite(model, image_path):
    import tensorflow as tf

    names = names_from_tflite(model)
    interp = tf.lite.Interpreter(model_path=model)
    interp.allocate_tensors()
    inp, outp = interp.get_input_details()[0], interp.get_output_details()[0]
    print("input ", inp["shape"], inp["dtype"], inp["quantization"])
    print("output", outp["shape"], outp["dtype"], outp["quantization"])

    im = working_image(image_path)
    x, r, px, py = letterbox(im)
    interp.set_tensor(inp["index"], x)
    interp.invoke()
    raw = interp.get_tensor(outp["index"])
    box_max = float(np.abs(raw[0, :4]).max())
    normalized = box_max <= 1.5
    print(f"box channel max = {box_max:.3f} -> {'normalized 0-1' if normalized else 'pixels'}")
    print(f"class score range = [{raw[0, 4:].min():.4f}, {raw[0, 4:].max():.4f}]")

    dets, _ = decode(raw, normalized)
    print(f"\nTFLite ({im.width}x{im.height}): {len(dets)} detections")
    for c, s, b in dets:
        b = [(b[0] - px) / r, (b[1] - py) / r, (b[2] - px) / r, (b[3] - py) / r]
        print(f"  {c}:{names[c]} {s:.3f} [{b[0]:.0f}, {b[1]:.0f}, {b[2]:.0f}, {b[3]:.0f}]")


def run_pt(pt, image_path):
    from ultralytics import YOLO

    im = working_image(image_path)
    res = YOLO(pt).predict(im, imgsz=SIZE, conf=CONF, iou=IOU, verbose=False)[0]
    print(f"\n.pt ({im.width}x{im.height}): {len(res.boxes)} detections")
    for c, s, b in sorted(zip(res.boxes.cls.tolist(), res.boxes.conf.tolist(),
                              res.boxes.xyxy.tolist()), key=lambda t: -t[1]):
        print(f"  {int(c)}:{res.names[int(c)]} {s:.3f} [{b[0]:.0f}, {b[1]:.0f}, {b[2]:.0f}, {b[3]:.0f}]")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--tflite", required=True)
    ap.add_argument("--pt")
    args = ap.parse_args()
    run_tflite(args.tflite, args.image)
    if args.pt:
        run_pt(args.pt, args.image)
