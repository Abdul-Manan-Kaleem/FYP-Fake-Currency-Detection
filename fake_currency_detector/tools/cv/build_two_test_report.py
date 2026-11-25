"""10-fold cross-validation report (PDF) for the two tests that were completed:
the monument classifier and the Rs 5,000 genuine-vs-altered classifier.

    python build_two_test_report.py --results DIR --out DIR
"""
import argparse
import json
import os
import statistics as st
import subprocess

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np


def pct(v):
    return f'{v * 100:.2f}%'


def table(header, rows, cls=''):
    h = ''.join(f'<th>{c}</th>' for c in header)
    b = ''.join('<tr>' + ''.join(f'<td>{c}</td>' for c in r) + '</tr>' for r in rows)
    return f'<table class="{cls}"><thead><tr>{h}</tr></thead><tbody>{b}</tbody></table>'


def bar(path, title, xs, ys, color, ylabel):
    fig, ax = plt.subplots(figsize=(7, 3.0), dpi=150)
    ax.bar(xs, [y * 100 for y in ys], color=color, width=0.65)
    m = sum(ys) / len(ys) * 100
    ax.axhline(m, color='#C62828', ls='--', lw=1.2, label=f'mean {m:.2f}%')
    for x, y in zip(xs, ys):
        ax.text(x, y * 100 + 0.25, f'{y * 100:.1f}', ha='center', fontsize=7)
    ax.set_ylim(max(0, min(ys) * 100 - 8), min(100.8, max(ys) * 100 + 3))
    ax.set_xticks(xs)
    ax.set_xlabel('Fold')
    ax.set_ylabel(ylabel + ' (%)')
    ax.set_title(title, fontsize=10)
    ax.legend(fontsize=8, loc='lower right')
    ax.spines[['top', 'right']].set_visible(False)
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--results', required=True)
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    mon = json.load(open(os.path.join(a.results, 'cv_monument.json'), encoding='utf8'))
    r5 = json.load(open(os.path.join(a.results, 'cv_rs5000.json'), encoding='utf8'))
    if len(mon['folds']) != 10 or len(r5['folds']) != 10:
        raise SystemExit('Both tests need all 10 folds.')

    ma = [f['accuracy'] for f in mon['folds']]
    ra = [f['accuracy'] for f in r5['folds']]
    bar(os.path.join(a.out, 'fig_mon.png'), 'Monument classifier: accuracy per fold',
        list(range(1, 11)), ma, '#1F3A5F', 'Accuracy')
    bar(os.path.join(a.out, 'fig_r5.png'), 'Rs 5,000 classifier: accuracy per fold',
        list(range(1, 11)), ra, '#2E7D32', 'Accuracy')

    H = []
    H.append('<h1>10-Fold Cross-Validation Report</h1>')
    H.append('<p class="sub">Pakistani Currency Note Screening System &middot; Final Year Project, '
             'Riphah International University</p>')
    H.append('<p>Two models were tested with 10-fold cross-validation: the <b>monument classifier</b> and the '
             '<b>Rs 5,000 genuine-vs-altered classifier</b>. Both ran to completion, all 10 folds each.</p>')

    # summary
    def row(test, model, metric, v):
        return [test, model, metric, pct(st.mean(v)), pct(st.pstdev(v)), pct(min(v)), pct(max(v))]
    H.append('<h2>1. Summary</h2>')
    H.append(table(['Test', 'Model', 'Metric', 'Mean', 'Std dev', 'Worst fold', 'Best fold'], [
        row('Monument classifier (back of the note)', 'MobileNetV2', 'Accuracy', ma),
        row('Rs 5,000 genuine vs altered (patch level)', 'MobileNetV3-Large', 'Accuracy', ra)]))
    H.append(f'<p>The monument classifier averaged <b>{pct(st.mean(ma))}</b> accuracy with a spread of only '
             f'{pct(st.pstdev(ma))} between folds. The Rs 5,000 classifier averaged <b>{pct(st.mean(ra))}</b> '
             f'accuracy (mean AUC {st.mean(f["auc"] for f in r5["folds"]):.3f}) with a spread of '
             f'{pct(st.pstdev(ra))}.</p>')

    # method
    H.append('<h2>2. Method</h2>')
    H.append('<h3>2.1 What 10-fold cross-validation does</h3>')
    H.append('<p>The photos are split into 10 parts (folds). Ten new models are trained, each time on 9 parts, '
             'and each is tested on the 1 part it never saw. The ten test scores are then averaged. Every photo '
             'is used for testing exactly once.</p>')
    H.append('<h3>2.2 How the folds were made</h3><ul>'
             '<li><b>Stratified</b>: every fold has about the same class mix.</li>'
             '<li><b>Grouped</b>: photos taken in the same minute (several shots of one note) stay in the same '
             'fold, so a near-identical photo never sits in both training and test parts '
             '(Rs 5,000: each photo is its own group, and a photo and its altered copy always share a fold).</li>'
             '<li><b>De-duplicated</b>: Roboflow augmented copies (names containing ".rf.") are reduced to one '
             'copy per source photo.</li>'
             '<li><b>Repeatable</b>: fixed seed 7. The fold models are discarded; nothing is installed in the '
             'app.</li></ul>')
    H.append('<h3>2.3 Data and model per test</h3>')
    H.append(table(['Test', 'Data', 'Model and training in each fold'], [
        ['Monument classifier',
         'DataSet_sorted: 1,217 monument-back photos (Rs 10: 163, Rs 20: 176, Rs 50: 172, Rs 100: 175, Rs 500: 182, '
         'Rs 1,000: 175, Rs 5,000: 174) and 1,688 "invalid" photos (fronts and other views) = 2,905 photos, '
         '8 classes. 672 photos where the side was unclear were left out.',
         'MobileNetV2 (ImageNet weights), letterbox 224 &times; 224, 12 epochs training the head, then 6 epochs '
         'fine-tuning (tools/train_monument.py).'],
        ['Rs 5,000 genuine vs altered',
         'DataSet/5000: 467 photos. For each photo, one cell of the 8 &times; 4 patch grid is taken either '
         'original (genuine) or after one synthetic localised alteration (blur, noise, brightness, contrast, '
         'colour shift, texture noise or partial obstruction): 934 samples, 467 per class.',
         'MobileNetV3-Large (ImageNet weights), whole network fine-tuned, 8 epochs, AdamW 5e-4, batch 32, '
         '112 &times; 112 px patches.']], 'wide'))
    H.append('<h3>2.4 Metrics</h3>')
    H.append(table(['Metric', 'Meaning'], [
        ['Accuracy', 'Share of test samples classified correctly.'],
        ['Precision', 'Of the samples called altered, the share that really were.'],
        ['Recall', 'Of the really altered samples, the share caught.'],
        ['F1', 'Harmonic mean of precision and recall.'],
        ['AUC', 'How well the two classes are separated over all thresholds (1.0 perfect, 0.5 chance).'],
        ['TP / TN / FP / FN', 'Altered called altered / genuine called genuine / genuine called altered / '
                              'altered called genuine.'],
        ['Std dev', 'Spread of the score across the ten folds.']], 'wide'))

    # monument
    H.append('<h2>3. Test 1: Monument classifier (MobileNetV2)</h2>')
    H.append('<p>The classifier looks at the back of the note. Each note value must show its own monument '
             '(for example Rs 100: Ziarat Residency, Rs 5,000: Faisal Mosque). A front, a photocopy or a wrong '
             'monument is "invalid". It is an 8-class problem, so accuracy and per-class accuracy are reported; '
             'precision, recall and TP/TN/FP/FN for a single class do not apply.</p>')
    H.append('<img src="fig_mon.png">')
    H.append(table(['Fold', 'Training photos', 'Test photos', 'Accuracy'],
                   [[f['fold'], f['train_photos'], f['test_photos'], pct(f['accuracy'])] for f in mon['folds']] +
                   [['<b>Mean</b>', '', '', f'<b>{pct(st.mean(ma))}</b>'],
                    ['<b>Std dev</b>', '', '', f'<b>{pct(st.pstdev(ma))}</b>']]))
    classes = mon['summary']['classes']
    rows = []
    for c in classes:
        v = [f['per_class'][c]['accuracy'] for f in mon['folds'] if f['per_class'].get(c, {}).get('accuracy') is not None]
        n = sum(f['per_class'][c]['test_photos'] for f in mon['folds'])
        rows.append([('Rs ' + c.split('_')[1]) if c != 'invalid' else 'invalid', n, len(v), pct(st.mean(v)),
                     pct(min(v)), pct(max(v))])
    H.append('<h3>Per-class accuracy</h3>')
    H.append(table(['Class', 'Test photos (all folds)', 'Folds with this class', 'Mean', 'Worst fold', 'Best fold'], rows))
    H.append('<p class="note">Some classes have few photo groups (for example Rs 1,000), so in a few folds that '
             'class had no test photos; its mean uses only the folds where it appeared.</p>')

    # rs5000
    H.append('<h2>4. Test 2: Rs 5,000 genuine vs altered (MobileNetV3-Large)</h2>')
    H.append('<p>The Rs 5,000 classifier decides whether a part of the note looks original or altered. On a '
             'whole photo the synthetic alteration covers under 1% of the pixels, so the test works at '
             '<b>patch level</b>: each sample is one cell of the 8 &times; 4 grid, shown original or altered.</p>')
    H.append('<img src="fig_r5.png">')
    keys = ['accuracy', 'precision', 'recall', 'f1']
    mean = ['<b>Mean</b>', ''] + [f'<b>{pct(st.mean(f[k] for f in r5["folds"]))}</b>' for k in keys] + \
           [f'<b>{st.mean(f["auc"] for f in r5["folds"]):.4f}</b>', '', '', '', '']
    sd = ['<b>Std dev</b>', ''] + [f'<b>{pct(st.pstdev(f[k] for f in r5["folds"]))}</b>' for k in keys] + \
         [f'<b>{st.pstdev(f["auc"] for f in r5["folds"]):.4f}</b>', '', '', '', '']
    H.append(table(['Fold', 'Test samples', 'Accuracy', 'Precision', 'Recall', 'F1', 'AUC', 'TP', 'TN', 'FP', 'FN'],
                   [[f['fold'], f['test_photos'], pct(f['accuracy']), pct(f['precision']), pct(f['recall']),
                     pct(f['f1']), f'{f["auc"]:.4f}', f['tp'], f['tn'], f['fp'], f['fn']] for f in r5['folds']] +
                   [mean, sd]))
    tp = sum(f['tp'] for f in r5['folds']); tn = sum(f['tn'] for f in r5['folds'])
    fp = sum(f['fp'] for f in r5['folds']); fn = sum(f['fn'] for f in r5['folds'])
    H.append(f'<p>Over all ten folds: {tp} altered samples caught, {fn} missed; {tn} genuine samples passed, '
             f'{fp} wrongly called altered (934 samples in total).</p>')

    # limits
    H.append('<h2>5. Limits</h2><ul>'
             '<li>The models trained for cross-validation are <b>fresh models</b>, not the exact weights '
             'bundled in the app. The figures show how well each method works on photos it has not seen.</li>'
             '<li>The Rs 5,000 test uses <b>synthetic alterations</b>; real counterfeit notes differ from them.</li>'
             '<li>The Rs 5,000 photos form one group per photo, so photos taken close together can still be '
             'similar across folds.</li>'
             '<li>Photos come from one collection taken under similar conditions. Real-world photos (other '
             'phones, lighting, worn notes) may score lower.</li></ul>')

    # repeat
    H.append('<h2>6. How to repeat</h2><p>Run from <code>fake_currency_detector/</code>:</p><pre>'
             'python tools/train_monument.py --sorted DataSet_sorted --folds 10 --cv-report cv_monument.json\n'
             'python tools/cv/cv_rs5000.py --data DataSet/5000 --out cv_rs5000.json</pre>')

    css = ('<style>@page{margin:16mm}body{font-family:Arial,sans-serif;font-size:10pt;color:#222}'
           'h1{color:#1F3A5F;font-size:22pt;margin-bottom:2px}h2{color:#1F3A5F;border-bottom:2px solid #1F3A5F;'
           'padding-bottom:2px;margin-top:20px}h3{color:#1F3A5F;margin-bottom:4px}.sub{color:#555;margin-top:0}'
           'table{border-collapse:collapse;width:100%;font-size:8.5pt;margin:6px 0 10px}'
           'th{background:#1F3A5F;color:#fff;padding:4px 5px}td{border:1px solid #999;padding:3px 5px;'
           'text-align:center}tr:nth-child(even) td{background:#EEF2F7}table.wide td{text-align:left}'
           'img{width:100%;max-width:16cm;display:block;margin:6px auto}pre,code{background:#f2f2f2}'
           'pre{padding:6px;font-size:8pt}.note{font-size:8.5pt;color:#555}h2{page-break-after:avoid}'
           'table{page-break-inside:avoid}</style>')
    base = os.path.join(a.out, '10_Fold_Cross_Validation_Report')
    open(base + '.html', 'w', encoding='utf8').write(
        '<html><head><meta charset="utf-8"><title>10-Fold Cross-Validation Report</title>' + css +
        '</head><body>' + '\n'.join(H) + '</body></html>')
    edge = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
    subprocess.run([edge, '--headless', '--disable-gpu', f'--print-to-pdf={base}.pdf', '--no-pdf-header-footer',
                    base + '.html'], capture_output=True)
    print('PDF written:', os.path.exists(base + '.pdf'))


if __name__ == '__main__':
    main()
