"""Report (PDF) about the Quaid-e-Azam portrait classifier.

    python build_portrait_report.py --out DIR

All numbers come from the training log and portrait_model_info.json of the run
on 2026-11-25 (tools/train_monument.py --kind portrait).
"""
import argparse
import os
import subprocess


def table(header, rows, cls=''):
    h = ''.join(f'<th>{c}</th>' for c in header)
    b = ''.join('<tr>' + ''.join(f'<td>{c}</td>' for c in r) + '</tr>' for r in rows)
    return f'<table class="{cls}"><thead><tr>{h}</tr></thead><tbody>{b}</tbody></table>'


classes = ['portrait_10', 'portrait_20', 'portrait_50', 'portrait_100', 'portrait_500',
           'portrait_1000', 'portrait_5000', 'invalid']
photos = [175, 259, 258, 260, 268, 250, 218, 1217]
test = [35, 53, 57, 54, 56, 87, 46, 260]

H = []
A = H.append
A('<h1>Quaid-e-Azam Portrait Classifier</h1>')
A('<p class="sub">Newly trained model for the front-side portrait check &middot; Pakistani Currency Note '
  'Screening System &middot; Final Year Project, Riphah International University</p>')

A('<h2>1. Summary</h2>')
A('<p>The app already checked the picture on the <b>back</b> of a note (the monument). This new model adds the '
  'matching check for the <b>front</b>: the Quaid-e-Azam (Muhammad Ali Jinnah) portrait side. It is an image '
  'classifier that looks at the whole front photo and answers: <i>which note value\'s front design is this, or is '
  'this not a valid front?</i> The answer is compared with the denomination found by YOLO11s. A confident mismatch '
  'makes the note FAKE.</p>')
A(table(['Item', 'Detail'], [
    ['Task', '8-class image classification of the front of a note (7 values + "invalid")'],
    ['Architecture', 'MobileNetV2 (ImageNet weights), new 8-class softmax head'],
    ['Input', '224 &times; 224 RGB, whole photo letterboxed on grey 114, pixels scaled x / 127.5 - 1'],
    ['Model file', '<code>assets/models/portrait_classifier.tflite</code> (8.5 MB, float32)'],
    ['Data', '2,905 photos: 1,688 fronts (7 values) + 1,217 backs as "invalid"'],
    ['Held-out test', '648 photos: 100% correct in every class'],
    ['Trained', '2026-11-25, on the CPU of the project computer'],
    ['Script', '<code>tools/train_monument.py --kind portrait</code>']]))

A('<h2>2. Why this check, and where it fits</h2>')
A('<p>Every Pakistani note carries the Quaid-e-Azam portrait on the front, with a design and colour scheme that is '
  'different for each value. The monument check already proves the back belongs to the claimed value; the portrait '
  'check proves the same for the front. A note whose front and back come from different values, or a front that is '
  'not a note front at all, is caught by one of the two checks. The two pictures are shown side by side in the '
  'results screen with the other security features (serial numbers, SBP seals, dots/lines, thread, printed year).</p>')

A('<h2>3. Dataset</h2>')
A('<p>The photos come from the project\'s main photo set (3,577 photos of the seven denominations, fronts and backs '
  'mixed in one folder per value). They were separated automatically, not by hand: the app\'s own YOLO11s model '
  'decides whether each photo shows the front or the back (the same sorting used for the monument model). A front '
  'becomes the class of its denomination folder; a back becomes <code>invalid</code>; photos where YOLO was unsure '
  'were left out.</p>')
A(table(['Class', 'Photos', 'Held-out test photos'],
        [[c, p, t] for c, p, t in zip(classes, photos, test)] +
        [['<b>Total</b>', f'<b>{sum(photos):,}</b>', f'<b>{sum(test)}</b>']], 'narrow'))
A('<p><b>How the split was made.</b> About 20% of each class was held out for testing. Photos taken in the same '
  'minute (several shots of one note) are kept together, so a near-identical photo never appears in both training '
  'and test. The held-out photos were never used to train the model or to choose its settings.</p>')

A('<h2>4. Model and training</h2>')
A('<h3>4.1 Architecture</h3>')
A('<p>MobileNetV2 pretrained on ImageNet, with its pooling output feeding <b>Dropout 0.25</b> and a '
  '<b>Dense(8, softmax)</b> layer. MobileNetV2 is small and fast enough to run on the phone in a few tens of '
  'milliseconds. It is the same family and the same training code as the monument classifier, so both checks '
  'behave in the same way.</p>')
A('<h3>4.2 Pre-processing</h3>')
A('<p>Each photo is kept whole (no cropping): its long side is scaled to 224 pixels and it is centred on a grey '
  '(114) square. Pixel values are scaled to the range -1 to 1. The phone does exactly the same steps, so '
  'training and use match.</p>')
A('<h3>4.3 Training steps</h3>')
A(table(['Stage', 'What', 'Settings'], [
    ['Augmentation', 'One extra altered copy of every training photo', 'Random 90&deg; turns, rotation &plusmn;12&deg;, '
     'zoom/shift (85-100%), brightness 0.6-1.35, contrast and colour 0.7-1.3, blur (35% of copies), JPEG quality 35-90 '
     '(50% of copies)'],
    ['Stage 1: head only', 'Backbone frozen, new head trained', '12 epochs, Adam, learning rate 1e-3, batch 32'],
    ['Stage 2: fine-tune', 'Last 30 layers of the backbone unfrozen', '6 epochs, Adam, learning rate 1e-5, batch 32'],
    ['Class weights', 'Balanced, so the larger "invalid" class does not dominate', 'weight = total / (8 &times; class size)'],
    ['Seed', 'Repeatable run', '7']]))
A('<h2>5. Results</h2>')
A('<h3>5.1 Held-out accuracy per class</h3>')
A(table(['Class', 'Test photos', 'Accuracy'], [[c, t, '100.0%'] for c, t in zip(classes, test)]))
A('<h3>5.2 Confusion matrix (rows = true class, columns = predicted)</h3>')
short = ['10', '20', '50', '100', '500', '1000', '5000', 'inv']
rows = []
for i, c in enumerate(short):
    rows.append([f'<b>{c}</b>'] + [str(test[i]) if i == j else '0' for j in range(8)])
A(table(['true \\ pred'] + short, rows, 'matrix'))
A('<p>All 648 held-out photos were classified correctly, so every off-diagonal cell is zero. The model is marked '
  '<b>verified</b> by the training script because every class reached at least 90% on at least 8 test photos.</p>')
A('<h3>5.3 Conversion to the phone</h3>')
A('<p>The Keras model was converted to TensorFlow Lite (float32, input [1, 224, 224, 3], output [1, 8]). The '
  'largest difference between the Keras and the TFLite probabilities on 20 test photos was <b>1.19 &times; 10<sup>-7</sup></b>, so '
  'the phone gives the same answers as the training computer.</p>')
A('<h3>5.4 How to read the 100%</h3>')
A('<p>100% on the held-out photos is real, but it reflects an <b>easy problem</b>: the seven front designs and the '
  'backs look very different from each other, and all photos come from the same collection and similar conditions. '
  'It shows the model has learned the front design of each value. It does <b>not</b> prove that the model can spot a '
  'forged portrait.</p>')

A('<h2>6. How the app uses it</h2>')
A(table(['Step', 'Where in the code'], [
    ['Load the model (optional: missing files only skip the check)', '<code>portrait_classifier.dart:111</code> (<code>tryLoad</code>)'],
    ['Run it on the front photo during analysis', '<code>on_device_currency_verification_repository.dart:609-614</code>'],
    ['Decide pass / fail', '<code>verification_engine.dart:1475</code> (<code>_portrait</code>)'],
    ['Show the row in the results screen', '<code>security_features_card.dart:87</code>'],
    ['Save the result in the scan history', '<code>features/history/data/scan_record.dart</code>']]))
A('<p><b>Decision rules (same as the monument check):</b></p><ul>'
  '<li><b>PASS</b>: the model sees the note\'s own value with confidence of 60% or more. It earns up to 10 points of '
  'the score (weight 10).</li>'
  '<li><b>FAIL, note is FAKE</b>: the model confidently (60% or more) sees another value\'s front, or "invalid".</li>'
  '<li><b>Not checked</b>: confidence below 60%. The app asks for a clearer photo; the note is never failed on a '
  'doubtful reading.</li>'
  '<li><b>Warning only</b>: if the model were not marked verified, a mismatch would only be reported.</li>'
  '<li><b>Skipped</b>: model files not installed, or the denomination is unknown.</li></ul>')
A('<p>Ten automated tests cover these cases (right portrait, wrong portrait, invalid, low confidence, unverified '
  'model, missing model, JSON round trip), and the whole suite of 217 tests passes.</p>')

A('<h2>7. Limitations</h2><ul>'
  '<li>It recognises the <b>front design</b> of each value. A good print or photocopy of the correct front would '
  'look right to this model; it is one check among several, not a forgery detector.</li>'
  '<li>The "invalid" class contains only <b>backs</b>. It has never seen photocopies, screens, other currencies or '
  'random objects, so its behaviour on those is not measured.</li>'
  '<li>The result comes from one train/test split, not a cross-validation. The 10-fold cross-validation in the '
  'project covers the monument classifier and the Rs 5,000 classifier only.</li>'
  '<li>All photos come from one collection under similar conditions; other phones, lighting and worn notes may '
  'lower the confidence (the app then reports "not checked", not a failure).</li></ul>')

A('<h2>8. Possible improvements</h2><ul>'
  '<li>Add photocopies, printouts and screen photos of notes to the "invalid" class.</li>'
  '<li>Add a YOLO class for the portrait box, so the classifier looks at the portrait region only and can notice '
  'a changed face.</li>'
  '<li>Run a 10-fold cross-validation for this model, as was done for the monument classifier.</li></ul>')

A('<h2>9. How to retrain</h2><pre>'
  '# 1. Sort the photos: portrait_&lt;value&gt; folders for fronts, invalid for backs (DataSet_portrait)\n'
  'python tools/train_monument.py --kind portrait --sorted DataSet_portrait --out portrait_model_out\n'
  '# 2. Copy portrait_classifier.tflite, portrait_labels.txt, portrait_model_info.json into assets/models/\n'
  '# 3. flutter build apk --release --split-per-abi</pre>')

css = ('<style>@page{margin:16mm}body{font-family:Arial,sans-serif;font-size:10pt;color:#222;line-height:1.38}'
       'h1{color:#1F3A5F;font-size:22pt;margin-bottom:2px}h2{color:#1F3A5F;border-bottom:2px solid #1F3A5F;'
       'padding-bottom:2px;margin-top:20px;page-break-after:avoid}h3{color:#1F3A5F;margin-bottom:4px;'
       'page-break-after:avoid}.sub{color:#555;margin-top:0}'
       'table{border-collapse:collapse;width:100%;font-size:8.8pt;margin:6px 0 10px}tr{page-break-inside:avoid}'
       'th{background:#1F3A5F;color:#fff;padding:4px 5px;text-align:left}'
       'td{border:1px solid #999;padding:3px 5px;vertical-align:top}tr:nth-child(even) td{background:#EEF2F7}'
       'table.narrow{width:60%}table.matrix td,table.matrix th{text-align:center}'
       'code{background:#f2f2f2;font-size:8.5pt}pre{background:#f2f2f2;padding:6px;font-size:8.2pt}</style>')

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    base = os.path.join(a.out, 'Quaid_e_Azam_Portrait_Model_Report')
    open(base + '.html', 'w', encoding='utf8').write(
        '<html><head><meta charset="utf-8"><title>Quaid-e-Azam Portrait Classifier</title>' + css +
        '</head><body>' + '\n'.join(H) + '</body></html>')
    edge = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
    subprocess.run([edge, '--headless', '--disable-gpu', f'--print-to-pdf={base}.pdf', '--no-pdf-header-footer',
                    base + '.html'], capture_output=True)
    print('PDF written:', os.path.exists(base + '.pdf'))
