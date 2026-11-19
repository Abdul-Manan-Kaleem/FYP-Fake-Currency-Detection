"""Final 10-fold cross-validation report (Markdown + PDF) for the three tests:
monument classifier, Rs 5,000 classifier and YOLO11s denomination detector.

    python build_final_report.py --results DIR --out DIR

Needs cv_monument.json, cv_rs5000.json and cv_yolo.json with all 10 folds; stops with an
error otherwise (no placeholders).
"""
import argparse
import json
import os
import statistics as st
import subprocess
import sys


def load(res, name, folds):
    p = os.path.join(res, name)
    if not os.path.exists(p):
        sys.exit(f'Missing {p}: that test has not finished.')
    d = json.load(open(p, encoding='utf8'))
    if len(d['folds']) != folds:
        sys.exit(f'{name} has {len(d["folds"])} of {folds} folds.')
    return d


def pct(v):
    return f'{v * 100:.2f}%'


def stats(vals):
    return st.mean(vals), (st.pstdev(vals) if len(vals) > 1 else 0.0), min(vals), max(vals)


def md_table(header, rows):
    out = ['| ' + ' | '.join(header) + ' |', '|' + '|'.join(['---'] * len(header)) + '|']
    out += ['| ' + ' | '.join(str(c) for c in r) + ' |' for r in rows]
    return '\n'.join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--results', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--folds', type=int, default=10)
    a = ap.parse_args()
    mon = load(a.results, 'cv_monument.json', a.folds)
    r5 = load(a.results, 'cv_rs5000.json', a.folds)
    yo = load(a.results, 'cv_yolo.json', a.folds)
    os.makedirs(a.out, exist_ok=True)

    L = []
    L.append('# 10-Fold Cross-Validation Report (FINAL)\n')
    L.append('Pakistani Currency Note Screening System - Final Year Project, Riphah International University\n')

    # ---- summary
    rows = []
    ma = [f['accuracy'] for f in mon['folds']]
    ra = [f['accuracy'] for f in r5['folds']]
    y50 = [f['map50'] for f in yo['folds']]
    for test, model, metric, v in (('Monument classifier (note back)', 'MobileNetV2', 'Accuracy', ma),
                                   ('Rs 5,000 genuine vs altered (patch level)', 'MobileNetV3-Large', 'Accuracy', ra),
                                   ('Note denomination detector', 'YOLO11s', 'mAP@0.50', y50)):
        m, s, lo, hi = stats(v)
        rows.append([test, model, metric, pct(m), pct(s), pct(lo), pct(hi)])
    L.append('## 1. Summary\n')
    L.append(md_table(['Test', 'Model', 'Metric', 'Mean', 'Std dev', 'Worst fold', 'Best fold'], rows) + '\n')

    # ---- method
    L.append('## 2. Method\n')
    L.append('### 2.1 How the folds were made\n')
    L += ['- **Stratified**: every fold has about the same class mix.',
          '- **Burst-grouped**: photos taken within the same minute stay in the same fold, so near-identical '
          'photos never sit in both training and test parts. (Rs 5,000: one group per photo, see section 4.)',
          '- **De-duplicated**: Roboflow augmented copies (names containing ".rf.") are reduced to one copy per '
          'source photo.',
          '- **Repeatable**: fixed seed 7, 10 folds. Nothing is installed into the app; the models trained for '
          'each fold are discarded.\n']
    L.append('### 2.2 Metrics\n')
    L.append(md_table(['Metric', 'Meaning'], [
        ['Accuracy', 'Share of test photos classified correctly.'],
        ['Precision', 'Of the notes called altered, the share that really were.'],
        ['Recall', 'Of the really altered notes, the share caught.'],
        ['F1', 'Harmonic mean of precision and recall.'],
        ['AUC', 'Separation of the two classes over all thresholds (1.0 perfect, 0.5 chance).'],
        ['TP / TN / FP / FN', 'Altered called altered / genuine called genuine / genuine called altered / '
                              'altered called genuine.'],
        ['mAP@0.50', 'Detection quality when a box counts as correct at 50% overlap.'],
        ['mAP@0.50-0.95', 'Stricter mAP averaged over overlaps from 50% to 95%.'],
        ['Std dev', 'Spread of the score across the ten folds (population standard deviation).']]) + '\n')
    L.append('### 2.3 Data and model per test\n')
    L.append(md_table(['Test', 'Data', 'Model and training in each fold'], [
        ['Monument', 'DataSet_sorted: monument backs (Rs 10, 20, 50, 100, 500, 1000, 5000) + "invalid" '
                     '(2,877 photos)', 'MobileNetV2, letterbox 224, 12 epochs head + 6 epochs fine-tune '
                                       '(tools/train_monument.py)'],
        ['Rs 5,000', 'DataSet/5000: 467 photos; each gives one genuine grid cell and the same cell with a '
                     'synthetic localised alteration',
         'MobileNetV3-Large (ImageNet), whole network, 8 epochs, AdamW 5e-4, 112 px patches'],
        ['YOLO11s', 'LargeDataset (Roboflow YOLOv4-PyTorch): 4,901 source photos, 7 denomination classes',
         f'YOLO11s (COCO weights), {yo["imgsz"]} px, {yo["epochs"]} epochs, '
         f'{yo.get("max_train") or "all"} training photos per fold, CPU']]) + '\n')

    # ---- monument
    L.append('## 3. Monument classifier (MobileNetV2)\n')
    L.append(md_table(['Fold', 'Training photos', 'Test photos', 'Accuracy', 'Precision', 'Recall', 'F1', 'AUC',
                       'TP', 'TN', 'FP', 'FN'],
                      [[f['fold'], f['train_photos'], f['test_photos'], pct(f['accuracy'])] + ['n/a'] * 8
                       for f in mon['folds']] +
                      [['Mean', '', '', pct(stats(ma)[0])] + [''] * 8, ['Std dev', '', '', pct(stats(ma)[1])] + [''] * 8]))
    L.append('\nThis is an 8-class problem, so precision, recall, F1, AUC and the TP/TN/FP/FN counts for a '
             'single positive class do not apply; per-class accuracy is given instead.\n')
    classes = mon['summary']['classes']
    rows = []
    for c in classes:
        v = [f['per_class'][c]['accuracy'] for f in mon['folds'] if f['per_class'].get(c, {}).get('accuracy') is not None]
        n = sum(f['per_class'][c]['test_photos'] for f in mon['folds'])
        rows.append([c, n, pct(stats(v)[0]), pct(stats(v)[1]), pct(min(v)), pct(max(v))])
    L.append(md_table(['Class', 'Test photos (all folds)', 'Mean', 'Std dev', 'Worst fold', 'Best fold'], rows) + '\n')

    # ---- rs5000
    L.append('## 4. Rs 5,000 genuine vs altered (MobileNetV3-Large)\n')
    L.append('Each sample is one cell of the 8 x 4 patch grid: the genuine cell or the same cell after one '
             'synthetic localised alteration (blur, noise, brightness, contrast, colour shift, texture noise or '
             'partial obstruction). On a whole photo the alteration covers under 1% of the pixels, so the test '
             'works at patch level. A photo and its altered copy always share a fold; folds are grouped by '
             'source photo.\n')
    rows = [[f['fold'], f['test_photos'], pct(f['accuracy']), pct(f['precision']), pct(f['recall']), pct(f['f1']),
             f'{f["auc"]:.4f}', f['tp'], f['tn'], f['fp'], f['fn']] for f in r5['folds']]
    keys = ['accuracy', 'precision', 'recall', 'f1']
    mean_row = ['Mean', ''] + [pct(stats([f[k] for f in r5['folds']])[0]) for k in keys] + \
               [f'{stats([f["auc"] for f in r5["folds"]])[0]:.4f}', '', '', '', '']
    sd_row = ['Std dev', ''] + [pct(stats([f[k] for f in r5['folds']])[1]) for k in keys] + \
             [f'{stats([f["auc"] for f in r5["folds"]])[1]:.4f}', '', '', '', '']
    L.append(md_table(['Fold', 'Test imgs', 'Accuracy', 'Precision', 'Recall', 'F1', 'AUC', 'TP', 'TN', 'FP', 'FN'],
                      rows + [mean_row, sd_row]) + '\n')

    # ---- yolo
    L.append('## 5. YOLO11s denomination detector\n')
    L.append(md_table(['Fold', 'Train photos', 'Test imgs', 'Precision', 'Recall', 'mAP@0.50', 'mAP@0.50-0.95'],
                      [[f['fold'], f['train_photos'], f['test_photos'], pct(f['precision']), pct(f['recall']),
                        pct(f['map50']), pct(f['map50_95'])] for f in yo['folds']] +
                      [['Mean', '', ''] + [pct(stats([f[k] for f in yo['folds']])[0]) for k in
                                           ('precision', 'recall', 'map50', 'map50_95')],
                       ['Std dev', '', ''] + [pct(stats([f[k] for f in yo['folds']])[1]) for k in
                                              ('precision', 'recall', 'map50', 'map50_95')]]))
    L.append('\nDetection has no genuine/fake classes, so TP/TN/FP/FN and AUC do not apply; precision and recall '
             'are the detector\'s box-level values at the default confidence threshold.\n')

    # ---- limits
    L.append('## 6. Limits\n')
    L += ['- The models trained for cross-validation are **fresh models**, not the exact weights inside the app. '
          'The figures show how well each method generalises to unseen photos.',
          '- The Rs 5,000 test uses **synthetic alterations** made with the project notebook\'s own functions; '
          'real counterfeit notes differ from them.',
          f'- YOLO11s was trained with a **reduced CPU budget** ({yo["imgsz"]} px, {yo["epochs"]} epochs, '
          f'{yo.get("max_train") or "all"} photos per fold) against the app model\'s 100 epochs at 640 px; '
          'the scores are a lower bound. Only the 7 denomination classes were tested (no security-feature boxes '
          'exist in the available dataset).',
          '- Photos came from the project team under similar conditions. **Real-world photos** (other phones, '
          'lighting, worn notes) may score lower.',
          '- Some monument classes have few photo groups (Rs 1000 has 8 for 10 folds), so a few folds hold no '
          'test photos of that class.\n']

    # ---- repeat
    L.append('## 7. How to repeat\n')
    L.append('Run from `fake_currency_detector/`:\n')
    L.append('```\npython tools/train_monument.py --sorted DataSet_sorted --folds 10 --cv-report cv_monument.json\n'
             'python tools/cv/cv_rs5000.py --data DataSet/5000 --out cv_rs5000.json\n'
             'python tools/cv/cv_yolo.py --data LargeDataset --work monument_work --out cv_yolo.json '
             f'--max-train {yo.get("max_train") or 0}\n'
             'python tools/cv/build_final_report.py --results . --out .\n```\n')

    base = os.path.join(a.out, '10_Fold_Cross_Validation_Report_FINAL')
    open(base + '.md', 'w', encoding='utf8').write('\n'.join(L))
    print('Wrote', base + '.md')
    try:
        import markdown  # noqa: F401
    except ImportError:
        subprocess.run([sys.executable, '-m', 'pip', 'install', 'markdown', '-q'])
    import markdown
    html = markdown.markdown('\n'.join(L), extensions=['tables', 'fenced_code'])
    css = ('<style>body{font-family:Arial;font-size:10pt;margin:2cm}table{border-collapse:collapse;width:100%;'
           'font-size:8pt}th,td{border:1px solid #888;padding:3px 5px;text-align:center}th{background:#1F3A5F;'
           'color:#fff}h1,h2,h3{color:#1F3A5F}code,pre{background:#f2f2f2}</style>')
    open(base + '.html', 'w', encoding='utf8').write('<html><head><meta charset="utf-8">' + css + '</head><body>' + html + '</body></html>')
    edge = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
    subprocess.run([edge, '--headless', '--disable-gpu', f'--print-to-pdf={base}.pdf', '--no-pdf-header-footer',
                    base + '.html'], capture_output=True)
    print('PDF:', os.path.exists(base + '.pdf'))


if __name__ == '__main__':
    main()
