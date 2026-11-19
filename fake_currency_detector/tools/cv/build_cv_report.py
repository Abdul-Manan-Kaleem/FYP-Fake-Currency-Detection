"""Build the 10-fold cross-validation report (Word + PDF) from the JSON result files.

    python build_cv_report.py --results DIR --out DIR

DIR holds cv_monument.json, cv_rs5000.json, cv_mnv3small_proxy.json and cv_yolo.json
(any that are missing are listed as "not run"). Produces:
    10_Fold_Cross_Validation_Report.docx   and   10_Fold_Cross_Validation_Report.pdf
"""
import argparse
import json
import os
import subprocess

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from docx import Document
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

NAVY = RGBColor(0x1F, 0x3A, 0x5F)
COLORS = ['#1F3A5F', '#2E7D32', '#B26A00', '#8E24AA']


PARTIAL = []     # names of tests built from unfinished runs


def load(res, name):
    """Final JSON if the run finished, otherwise the folds finished so far (<name>.partial)."""
    import numpy as np
    p = os.path.join(res, name)
    if os.path.exists(p):
        return json.load(open(p, encoding='utf8'))
    pp = p + '.partial'
    if not os.path.exists(pp):
        return None
    folds = json.load(open(pp, encoding='utf8'))
    if not folds:
        return None
    PARTIAL.append(f'{name}: {len(folds)} of 10 folds finished')
    if 'per_class' in folds[0]:                     # monument
        acc = np.array([f['accuracy'] for f in folds])
        classes = list(folds[0]['per_class'])
        return dict(folds=folds, summary=dict(mean_accuracy=float(acc.mean()), std_accuracy=float(acc.std()),
                                              min_accuracy=float(acc.min()), max_accuracy=float(acc.max()),
                                              classes=classes))
    keys = ['accuracy', 'precision', 'recall', 'f1', 'auc']
    import cv_common as cc
    return dict(folds=folds, bursts=0, summary=cc.summarise(folds, keys))


def pct(v):
    return f'{v * 100:.2f}%'


def shade(cell, hex_fill):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement('w:shd')
    shd.set(qn('w:val'), 'clear')
    shd.set(qn('w:color'), 'auto')
    shd.set(qn('w:fill'), hex_fill)
    tcPr.append(shd)


def table(doc, header, rows, widths=None, font=9):
    t = doc.add_table(rows=1, cols=len(header))
    t.style = 'Table Grid'
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    for i, h in enumerate(header):
        c = t.rows[0].cells[i]
        c.text = ''
        r = c.paragraphs[0].add_run(h)
        r.bold = True
        r.font.size = Pt(font)
        r.font.color.rgb = RGBColor(255, 255, 255)
        shade(c, '1F3A5F')
    for ri, row in enumerate(rows):
        cells = t.add_row().cells
        for i, v in enumerate(row):
            cells[i].text = ''
            run = cells[i].paragraphs[0].add_run(str(v))
            run.font.size = Pt(font)
            if i > 0:
                cells[i].paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
            if ri % 2:
                shade(cells[i], 'EEF2F7')
    if widths:
        for row in t.rows:
            for i, w in enumerate(widths):
                row.cells[i].width = Cm(w)
    doc.add_paragraph()
    return t


def para(doc, text, bold=False, italic=False, size=10.5, after=6):
    p = doc.add_paragraph()
    r = p.add_run(text)
    r.bold, r.italic = bold, italic
    r.font.size = Pt(size)
    p.paragraph_format.space_after = Pt(after)
    return p


def bullets(doc, items):
    for it in items:
        p = doc.add_paragraph(style='List Bullet')
        r = p.add_run(it)
        r.font.size = Pt(10.5)


def fold_chart(path, title, folds, key, label, color):
    xs = [f['fold'] for f in folds]
    ys = [f[key] * 100 for f in folds]
    fig, ax = plt.subplots(figsize=(7, 3.2), dpi=150)
    ax.bar(xs, ys, color=color, width=0.65)
    mean = sum(ys) / len(ys)
    ax.axhline(mean, color='#C62828', ls='--', lw=1.2, label=f'mean {mean:.2f}%')
    for x, y in zip(xs, ys):
        ax.text(x, y + 0.4, f'{y:.1f}', ha='center', fontsize=7)
    lo = max(0, min(ys) - 8)
    ax.set_ylim(lo, min(100.5, max(ys) + 4))
    ax.set_xticks(xs)
    ax.set_xlabel('Fold')
    ax.set_ylabel(label + ' (%)')
    ax.set_title(title, fontsize=10)
    ax.legend(fontsize=8, loc='lower right')
    ax.spines[['top', 'right']].set_visible(False)
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)


def heat(path, title, classes, folds):
    import numpy as np
    m = np.array([[f['per_class'].get(c, {}).get('accuracy', float('nan')) * 100 for c in classes] for f in folds])
    fig, ax = plt.subplots(figsize=(7, 3.6), dpi=150)
    im = ax.imshow(m, cmap='RdYlGn', vmin=60, vmax=100, aspect='auto')
    ax.set_xticks(range(len(classes)))
    ax.set_xticklabels([c.replace('monument_', 'Rs ') for c in classes], fontsize=7, rotation=30)
    ax.set_yticks(range(len(folds)))
    ax.set_yticklabels([f'Fold {f["fold"]}' for f in folds], fontsize=7)
    for i in range(m.shape[0]):
        for j in range(m.shape[1]):
            ax.text(j, i, f'{m[i, j]:.0f}', ha='center', va='center', fontsize=6)
    ax.set_title(title, fontsize=10)
    fig.colorbar(im, ax=ax, fraction=0.03)
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--results', required=True)
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    mon = load(a.results, 'cv_monument.json')
    r5 = load(a.results, 'cv_rs5000.json')
    sm = load(a.results, 'cv_mnv3small_proxy.json')
    yo = load(a.results, 'cv_yolo.json')
    old = load(a.results, 'cv_monument_rebuilt.json')

    doc = Document()
    sec = doc.sections[0]
    sec.left_margin = sec.right_margin = Cm(2.2)
    sec.top_margin = sec.bottom_margin = Cm(2.0)
    st = doc.styles['Normal']
    st.font.name = 'Calibri'
    st.font.size = Pt(10.5)
    for n, sz in (('Heading 1', 16), ('Heading 2', 13), ('Heading 3', 11)):
        doc.styles[n].font.name = 'Calibri'
        doc.styles[n].font.size = Pt(sz)
        doc.styles[n].font.color.rgb = NAVY

    # ---- title page
    for _ in range(5):
        doc.add_paragraph()
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run('10-Fold Cross-Validation Report')
    r.bold = True
    r.font.size = Pt(26)
    r.font.color.rgb = NAVY
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run('Pakistani Currency Note Screening System')
    r.font.size = Pt(16)
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run('Monument classifier  |  Rs 5,000 MobileNetV3-Large  |  MobileNetV3-Small  |  YOLO11s')
    r.font.size = Pt(11)
    for _ in range(3):
        doc.add_paragraph()
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.add_run('Final Year Project\nRiphah International University').font.size = Pt(12)
    doc.add_page_break()

    # ---- 1 summary
    doc.add_heading('1. Summary', 1)
    para(doc, 'Cross-validation answers one question: how well does each model work on photos it has never '
              'seen? The photos are split into 10 parts (folds). Ten new models are trained, each time on 9 '
              'parts, and each is tested on the 1 part it did not see. The ten test scores are then averaged. '
              'A model that only memorised its training photos would score well on the usual single test split '
              'but badly here.')
    rows = []
    if mon:
        s = mon['summary']
        rows.append(['Monument classifier (back side)', 'MobileNetV2, 8 classes', 'Accuracy',
                     pct(s['mean_accuracy']), pct(s['std_accuracy']), pct(s['min_accuracy']), pct(s['max_accuracy'])])
    if r5:
        s = r5['summary']['accuracy']
        rows.append(['Rs 5,000 genuine vs altered', 'MobileNetV3-Large', 'Accuracy',
                     pct(s['mean']), pct(s['std']), pct(s['min']), pct(s['max'])])
    if sm:
        s = sm['summary']['accuracy']
        rows.append(['Genuine vs altered, Rs 10-1000 (stand-in)', 'MobileNetV3-Small', 'Accuracy',
                     pct(s['mean']), pct(s['std']), pct(s['min']), pct(s['max'])])
    if yo:
        s = yo['summary']['map50']
        rows.append(['Note denomination detector', 'YOLO11s', 'mAP@0.50',
                     pct(s['mean']), pct(s['std']), pct(s['min']), pct(s['max'])])
    table(doc, ['Test', 'Model', 'Metric', 'Mean', 'Std dev', 'Worst fold', 'Best fold'], rows,
          [4.6, 3.2, 1.8, 1.6, 1.5, 1.8, 1.8], 8.5)
    if PARTIAL:
        para(doc, 'DRAFT: these tests were still running when this file was made. Means below use only the '
                  'folds finished so far: ' + '; '.join(PARTIAL) + '.', bold=True)
    for name, d in (('YOLO11s', yo), ):
        if d is None:
            para(doc, 'YOLO11s: not run yet.', italic=True)
    para(doc, 'Important limits of this report (details in section 7):', bold=True)
    bullets(doc, [
        'The Genuine / Fake photo folders used to train MobileNetV3-Small are not on this computer, and the '
        'Roboflow "Fake Currency Detection" set contains only 5 fake notes out of 3,626. MobileNetV3-Small was '
        'therefore tested on a stand-in (real notes vs. the same notes with a localised alteration), which is '
        'NOT the same as testing it on real counterfeit notes.',
        'The 13-class YOLO dataset (with security-feature boxes) is not on this computer either. Only the '
        '7 denomination boxes could be tested, with a much smaller training budget than the app model.',
        'Every figure was produced on a CPU with fresh models, not on the exact weights inside the app.'])
    doc.add_page_break()

    # ---- 2 method
    doc.add_heading('2. Method', 1)
    doc.add_heading('2.1 How the folds were made', 2)
    bullets(doc, [
        'Stratified: every fold has about the same mix of classes.',
        'Burst-grouped: photos taken within the same minute (several shots of one note) always stay in the '
        'same fold. Without this, a near-identical photo would sit in training and in the test part and the '
        'score would be inflated.',
        'De-duplicated: Roboflow writes several augmented copies of one photo (names containing ".rf."). Only '
        'one copy per source photo is used.',
        'Repeatable: shuffled with a fixed seed (7); the same command gives the same folds.',
        'Nothing is installed into the app: the cross-validation models are thrown away after testing.'])
    doc.add_heading('2.2 Metrics', 2)
    table(doc, ['Metric', 'Meaning'], [
        ['Accuracy', 'Share of test photos classified correctly.'],
        ['Precision', 'Of the notes called "fake/altered", the share that really were.'],
        ['Recall', 'Of the really fake/altered notes, the share that were caught. A low value means fakes slip through.'],
        ['F1', 'Balance of precision and recall (harmonic mean).'],
        ['AUC', 'How well the model separates the two classes at any threshold (1.0 = perfect, 0.5 = chance).'],
        ['mAP@0.50', 'Detection quality: a box counts as correct when it overlaps the true box by at least 50%.'],
        ['mAP@0.50-0.95', 'Stricter version averaged over overlap thresholds from 50% to 95%.'],
        ['Std dev', 'How much the score changes from fold to fold. Small = stable model.']], [3.4, 13])
    doc.add_heading('2.3 Data and model used for each test', 2)
    table(doc, ['Test', 'Photos', 'Classes / task', 'Training setup in each fold'], [
        ['Monument', 'DataSet folder (3,577 photos, 7 denomination folders); YOLO11s separated backs from fronts: '
                     '1,189 monument backs + 1,688 other (fronts) = 2,877 used, 672 unsure photos left out',
         '8 classes: Rs 10, 20, 50, 100, 500, 1000, 5000 monument + "invalid"',
         'MobileNetV2 (ImageNet), letterbox 224, 12 epochs head + 6 epochs fine-tune, as tools/train_monument.py'],
        ['Rs 5,000', 'DataSet/5000: 467 photos; each gives one genuine grid cell and the same cell altered',
         'genuine / altered (patch level)', 'MobileNetV3-Large (ImageNet), fine-tuned whole, 8 epochs, AdamW 5e-4, '
                                            '112 px patches'],
        ['MobileNetV3-Small', 'DataSet Rs 10, 20, 50, 100, 500, 1000: genuine + altered copies',
         'genuine / altered (stand-in)', 'Frozen MobileNetV3-Small features + Dropout 0.30 + Dense(1, sigmoid), '
                                          'Adam 1e-3, balanced weights, early stopping'],
        ['YOLO11s', 'LargeDataset (Roboflow, YOLOv4-PyTorch export), one copy per source photo',
         '7 denomination boxes', 'YOLO11s (COCO weights), reduced image size and epochs, CPU']],
        [2.6, 5.6, 3.6, 5.0], 8)
    doc.add_page_break()

    n = 3
    # ---- monument
    doc.add_heading(f'{n}. Monument classifier', 1)
    n += 1
    if mon:
        s = mon['summary']
        para(doc, 'The monument classifier checks the back of the note. A Rs 100 note must show Ziarat Residency, '
                  'Rs 5,000 must show Faisal Mosque, and so on. A front photo, a photocopy or a wrong monument '
                  'is "invalid" and makes the verdict FAKE.')
        fold_chart(os.path.join(a.out, 'fig_monument.png'), 'Monument classifier: accuracy per fold',
                   mon['folds'], 'accuracy', 'Accuracy', COLORS[0])
        doc.add_picture(os.path.join(a.out, 'fig_monument.png'), width=Cm(14.5))
        para(doc, f'Mean accuracy {pct(s["mean_accuracy"])}, standard deviation {pct(s["std_accuracy"])}, '
                  f'range {pct(s["min_accuracy"])} to {pct(s["max_accuracy"])}.', bold=True)
        table(doc, ['Fold', 'Training photos', 'Test photos', 'Accuracy'],
              [[f['fold'], f['train_photos'], f['test_photos'], pct(f['accuracy'])] for f in mon['folds']] +
              [['Mean', '', '', pct(s['mean_accuracy'])]], [2, 4, 4, 4])
        classes = s['classes']
        heat(os.path.join(a.out, 'fig_monument_heat.png'), 'Accuracy (%) per class and fold', classes, mon['folds'])
        doc.add_picture(os.path.join(a.out, 'fig_monument_heat.png'), width=Cm(14.5))
        rows = []
        for c in classes:
            v = [f['per_class'].get(c, {}).get('accuracy') for f in mon['folds']]
            v = [x for x in v if x is not None]
            tp = sum(f['per_class'].get(c, {}).get('test_photos', 0) for f in mon['folds'])
            rows.append([c.replace('monument_', 'Rs ') if c != 'invalid' else 'invalid (not a back / not a monument)',
                         tp, pct(sum(v) / len(v)) if v else '-', pct(min(v)) if v else '-', pct(max(v)) if v else '-'])
        para(doc, 'Per-class accuracy across the ten folds:', bold=True)
        table(doc, ['Class', 'Test photos (all folds)', 'Mean', 'Worst fold', 'Best fold'], rows, [6, 3.4, 2.4, 2.4, 2.4])
    else:
        para(doc, 'Not run.', italic=True)

    doc.add_page_break()
    # ---- rs5000
    doc.add_heading(f'{n}. Rs 5,000 genuine-vs-altered classifier (MobileNetV3-Large)', 1)
    n += 1
    if r5:
        para(doc, 'Each Rs 5,000 photo is paired with a copy that has one localised alteration (blur, noise, '
                  'brightness, contrast, colour shift, texture noise or a partial obstruction in one of 32 patches). '
                  'The test works at patch level: each sample is the grid cell that was altered, shown either '
                  'original or altered, because on a whole photo the change covers under 1% of the pixels. '
                  'A photo and its altered copy always stay in the same fold.')
        fold_chart(os.path.join(a.out, 'fig_rs5000.png'), 'Rs 5,000 classifier: accuracy per fold',
                   r5['folds'], 'accuracy', 'Accuracy', COLORS[1])
        doc.add_picture(os.path.join(a.out, 'fig_rs5000.png'), width=Cm(14.5))
        s = r5['summary']
        para(doc, f'Mean accuracy {pct(s["accuracy"]["mean"])}, std {pct(s["accuracy"]["std"])}; '
                  f'mean recall (altered caught) {pct(s["recall"]["mean"])}; mean AUC {s["auc"]["mean"]:.3f}.', bold=True)
        table(doc, ['Fold', 'Test imgs', 'Accuracy', 'Precision', 'Recall', 'F1', 'AUC', 'TP', 'TN', 'FP', 'FN'],
              [[f['fold'], f['test_photos'], pct(f['accuracy']), pct(f['precision']), pct(f['recall']),
                pct(f['f1']), f'{f["auc"]:.3f}', f['tp'], f['tn'], f['fp'], f['fn']] for f in r5['folds']] +
              [['Mean', '', pct(s['accuracy']['mean']), pct(s['precision']['mean']), pct(s['recall']['mean']),
                pct(s['f1']['mean']), f'{s["auc"]["mean"]:.3f}', '', '', '', '']],
              None, 8)
        para(doc, f'The Rs 5,000 photos fall into only {r5["bursts"]} burst groups, so some folds are smaller or '
                  'larger than others (see "Test imgs").', italic=True)
    else:
        para(doc, 'Not run.', italic=True)

    doc.add_page_break()
    doc.add_heading(f'{n}. MobileNetV3-Small classifier (Rs 10, 20, 50, 100, 500, 1000)', 1)
    n += 1
    if sm:
        para(doc, 'STAND-IN TEST. The model in the app was trained on Genuine and Fake photo folders that are '
                  'not available here. This table measures the same architecture on genuine photos versus the '
                  'same photos with a localised alteration. It shows the model type learns this kind of '
                  'difference; it does NOT measure how well the app detects real counterfeit notes.', bold=True)
        fold_chart(os.path.join(a.out, 'fig_small.png'), 'MobileNetV3-Small (stand-in): accuracy per fold',
                   sm['folds'], 'accuracy', 'Accuracy', COLORS[2])
        doc.add_picture(os.path.join(a.out, 'fig_small.png'), width=Cm(14.5))
        s = sm['summary']
        table(doc, ['Fold', 'Test imgs', 'Accuracy', 'Precision', 'Recall', 'F1', 'AUC'],
              [[f['fold'], f['test_photos'], pct(f['accuracy']), pct(f['precision']), pct(f['recall']),
                pct(f['f1']), f'{f["auc"]:.3f}'] for f in sm['folds']] +
              [['Mean', '', pct(s['accuracy']['mean']), pct(s['precision']['mean']), pct(s['recall']['mean']),
                pct(s['f1']['mean']), f'{s["auc"]["mean"]:.3f}']], None, 8.5)
    else:
        para(doc, 'Not run.', italic=True)

    doc.add_page_break()
    doc.add_heading(f'{n}. YOLO11s denomination detector', 1)
    n += 1
    if yo:
        para(doc, f'Reduced budget: image size {yo["imgsz"]} px, {yo["epochs"]} epochs'
                  + (f', at most {yo["max_train"]} training photos per fold' if yo.get('max_train') else '')
                  + ', COCO starting weights, CPU. The app model was trained for up to 100 epochs at 640 px on a '
                    'GPU, so these numbers are a lower bound.')
        fold_chart(os.path.join(a.out, 'fig_yolo.png'), 'YOLO11s: mAP@0.50 per fold', yo['folds'], 'map50',
                   'mAP@0.50', COLORS[3])
        doc.add_picture(os.path.join(a.out, 'fig_yolo.png'), width=Cm(14.5))
        s = yo['summary']
        table(doc, ['Fold', 'Train', 'Test', 'Precision', 'Recall', 'mAP@0.50', 'mAP@0.50-0.95'],
              [[f['fold'], f['train_photos'], f['test_photos'], pct(f['precision']), pct(f['recall']),
                pct(f['map50']), pct(f['map50_95'])] for f in yo['folds']] +
              [['Mean', '', '', pct(s['precision']['mean']), pct(s['recall']['mean']), pct(s['map50']['mean']),
                pct(s['map50_95']['mean'])]], None, 8.5)
    else:
        para(doc, 'Not run.', italic=True)

    doc.add_page_break()
    doc.add_heading(f'{n}. Limits and how to read these numbers', 1)
    n += 1
    bullets(doc, [
        'Cross-validation models are fresh models trained here. They show how well each method generalises to '
        'new photos; they are not the exact weights shipped in the app.',
        'MobileNetV3-Small: real counterfeit photos were not available, so only the stand-in test was possible. '
        'To test the real thing, place the Genuine and Fake folders on this computer and run '
        'tools/cv/cv_mnv3small.py --data <folder>; the script is ready.',
        'YOLO11s: security-feature boxes (dots, lines, thread, SBP seal, serial, year) are not in any dataset on '
        'this computer, so only denomination detection was tested, with a small CPU budget.',
        'The sorting of the monument photos into backs and fronts was done by the app\'s own YOLO11s model, so '
        'any side the YOLO model mistakes would carry into the monument labels. 672 uncertain photos were left out.',
        'All photos were taken by the project team in similar conditions. Real-world photos (other phones, '
        'lighting, worn notes) can score lower than any figure here.',
        'Rs 5,000 and stand-in tests use synthetic alterations. Real counterfeits differ from them.'])

    doc.add_heading(f'{n}. How to repeat the tests', 1)
    para(doc, 'All scripts are in fake_currency_detector/tools/cv/ (monument: tools/train_monument.py --folds 10).')
    table(doc, ['Test', 'Command (run from the repository folder)'], [
        ['Monument', 'python tools/train_monument.py --labelled DataSet   (sort once)\n'
                     'python tools/train_monument.py --sorted DataSet_sorted --folds 10 --cv-report cv_monument.json'],
        ['Rs 5,000', 'python tools/cv/cv_rs5000.py --data DataSet/5000 --out cv_rs5000.json'],
        ['MobileNetV3-Small', 'python tools/cv/cv_mnv3small.py --data <Genuine/Fake folder> --out cv_small.json\n'
                              '(stand-in: --synthetic --data DataSet)'],
        ['YOLO11s', 'python tools/cv/cv_yolo.py --data <LargeDataset folder> --work yolo_work --out cv_yolo.json']],
        [3.2, 13.2], 8)
    if mon:
        para(doc, 'Run settings: seed 7, 10 folds; monument 12 + 6 epochs.', italic=True)

    base = os.path.join(a.out, '10_Fold_Cross_Validation_Report')
    doc.save(base + '.docx')
    soffice = r'C:\Program Files\LibreOffice\program\soffice.exe'
    subprocess.run([soffice, '--headless', '--convert-to', 'pdf', '--outdir', a.out, base + '.docx'],
                   check=False, capture_output=True)
    print('Wrote', base + '.docx', 'and', base + '.pdf')


if __name__ == '__main__':
    main()
