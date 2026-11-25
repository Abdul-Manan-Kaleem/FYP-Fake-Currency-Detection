"""Datasets, notebooks, models and integration: detailed breakdown (PDF).

    python build_breakdown_report.py --out DIR

Every figure comes from the project files: the three Colab notebooks, the Roboflow
dataset README files, the model info files, the integration guides and the app source.
Where the project files do not record something, the document says so.
"""
import argparse
import os
import subprocess


def table(header, rows, cls='wide'):
    h = ''.join(f'<th>{c}</th>' for c in header)
    b = ''.join('<tr>' + ''.join(f'<td>{c}</td>' for c in r) + '</tr>' for r in rows)
    return f'<table class="{cls}"><thead><tr>{h}</tr></thead><tbody>{b}</tbody></table>'


def kv(rows):
    return table(['Item', 'Detail'], rows)


H = []
A = H.append

A('<h1>Datasets, Notebooks, Models and Integration</h1>')
A('<p class="sub">Pakistani Currency Note Screening System &middot; Final Year Project, Riphah International '
  'University</p>')
A('<p>This document explains, in detail, what data the system was built on, what each training notebook does, '
  'how many models are used and how each was trained, and how the models were integrated into the Flutter '
  'app. Everything is taken from the project files; where a detail was not recorded, it is marked '
  '<i>not recorded</i> rather than guessed.</p>')

# ------------------------------------------------------------------ 1
A('<h2>1. Overview: how many models</h2>')
A('<p>The app bundles <b>five trained TensorFlow Lite models</b>. <b>Four are active</b>; the MobileNetV3-Small '
  'model is built in but switched off (<code>kSmallCnnEnabled = false</code>). Two Google ML Kit components '
  '(text recognition and the document scanner) are used as ready-made tools, not trained by the project.</p>')
A(table(['#', 'Model', 'Job', 'Architecture', 'App file (size)', 'Status'], [
    ['1', 'Note and feature detector', 'Finds the denomination and the security features on each side',
     'YOLO11s, 13 classes', 'yolo11s_currency.tflite (36.2 MB)', 'Active, every note'],
    ['2', 'Rs 5,000 alteration classifier', 'Probability that a Rs 5,000 note was altered',
     'MobileNetV3-Large, sigmoid head', 'rs5000_mobilenetv3large.tflite (3.3 MB)', 'Active, Rs 5,000 only'],
    ['3', 'Rs 5,000 genuine / counterfeit classifier', 'Probability that a Rs 5,000 note is counterfeit',
     'MobileNetV3-Large, 2-way head (PyTorch, converted)', 'mobilenetv3_pkr5000_counterfeit.tflite (16 MB)',
     'Active, Rs 5,000 only'],
    ['4', 'Monument classifier', 'Checks the picture on the back against the denomination',
     'MobileNetV2, 8 classes', 'monument_classifier.tflite (8.5 MB)', 'Active, every note'],
    ['5', 'Genuine / fake classifier', 'Genuine or fake for Rs 10, 20, 50, 100, 500, 1,000',
     'MobileNetV3-Small, sigmoid head', 'mobilenetv3small_final.tflite (3.6 MB)', 'Built in, switched off']]))

# ------------------------------------------------------------------ 2
A('<h2>2. Datasets</h2>')
A('<h3>2.1 Main photo set: <code>DataSet</code> (3,577 photos)</h3>')
A('<p>Photos of Pakistani notes of all seven denominations, one folder per denomination; '
  'fronts and backs are mixed inside each folder. File names show the source: phone-camera photos '
  '(<code>20260812_161846.jpg</code>), WhatsApp images (<code>WhatsApp Image 2026-08-09 ...jpeg</code>) and a few '
  'older photos (<code>IMG20220209...jpg</code>). Formats: 2,452 .jpg and 1,125 .jpeg.</p>')
A(table(['Denomination', 'Photos'], [
    ['Rs 10', '510'], ['Rs 20', '524'], ['Rs 50', '513'], ['Rs 100', '515'], ['Rs 500', '538'],
    ['Rs 1,000', '510'], ['Rs 5,000', '467'], ['<b>Total</b>', '<b>3,577</b>']], 'narrow'))
A('<p>This is the same set the Rs 5,000 notebook reads (3,577 photos, the counts above) and the source for the '
  'monument classifier and the Rs 5,000 classifiers. It holds only genuine notes. It carries no box labels, so it '
  'is not the YOLO training set.</p>')

A('<h3>2.2 Monument dataset: <code>DataSet_sorted</code></h3>')
A('<p>Built from the main photo set by <code>tools/train_monument.py --labelled</code>. The folder name gives the '
  'denomination; the app\'s own YOLO11s model decides the side: a back becomes <code>monument_&lt;value&gt;</code>, '
  'a front becomes <code>invalid</code>, and an unclear side is left out (<code>_unsure</code>).</p>')
A(table(['Class', 'Photos'], [
    ['monument_10', '163'], ['monument_20', '176'], ['monument_50', '172'], ['monument_100', '175'],
    ['monument_500', '182'], ['monument_1000', '175'], ['monument_5000', '174'],
    ['invalid (fronts and other views)', '1,688'], ['_unsure (left out)', '672'],
    ['<b>Total</b>', '<b>3,577</b>']], 'narrow'))
A('<p>The classifier shipped in the app was trained on 162 / 176 / 172 / 171 / 182 / 173 / 174 monument photos '
  'and 1,684 invalid photos (from its <code>monument_model_info.json</code>); the counts above are from sorting the '
  'same folder again.</p>')

A('<h3>2.3 YOLO dataset: Roboflow project <code>currency-security-features</code> (version 8)</h3>')
A('<p>The detector was trained on a Roboflow export of the team\'s annotated photos (downloaded in the notebook '
  'with the Roboflow API, YOLOv11 format). It has <b>13 classes</b>: the seven note values '
  '(1000Rs, 100Rs, 10Rs, 20Rs, 5000Rs, 500Rs, 50Rs Note) and six features: <code>printed_year</code>, '
  '<code>sbp_seal</code>, <code>security_dots</code>, <code>security_lines</code>, <code>security_thread</code>, '
  '<code>serial_number</code>.</p>')
A(table(['Split', 'Images found', 'Flagged corrupt and ignored', 'Images used', 'Boxes'], [
    ['Train', '5,420', '541', '4,879', 'not printed'],
    ['Validation', '774', '69', '705', '2,655'],
    ['Test', '388', '40', '348', '1,354']]))
A('<p>The "corrupt" images are ones where the label file mixed polygon (segment) rows with box rows; Ultralytics '
  'skips them. The images were split by Roboflow; names such as <code>20260812_161846_jpg.rf.&lt;hash&gt;.jpg</code> '
  'show that Roboflow wrote augmented copies of each source photo.</p>')

A('<h3>2.4 Public Roboflow set: <code>LargeDataset</code> (stored in the project data folder)</h3>')
A(kv([
    ['Source', 'Roboflow Universe, workspace "sadiaworkspace", project largedataset-0ohqp, licence CC BY 4.0'],
    ['Size', '10,086 images in total: 7,771 train, 1,157 validation, 1,158 test'],
    ['Classes', '8: the seven denominations (10, 20, 50, 100, 500, 1000, 5000 Rupees) plus one extra class "i"'],
    ['Annotation', 'Bounding boxes in YOLOv4-PyTorch format (also a VOC export)'],
    ['Preprocessing', 'Auto-orient, resize to 640 &times; 640 (stretch)'],
    ['Augmentation', 'Three versions per source image, random rotation -15 to +15 degrees'],
    ['Use in the final models', 'The final YOLO notebook trains on the project\'s own 13-class dataset (2.3), not on this one']]))

A('<h3>2.5 Fake / counterfeit datasets</h3>')
A('<p><b>(a) Genuine/Fake set used to train MobileNetV3-Small</b> (Google Drive folder '
  '<code>Currency_Counterfeit_Dataset</code> with sub-folders <code>Genuine</code> and <code>Fake</code>):</p>')
A(table(['Part', 'Genuine', 'Fake', 'Total'], [
    ['All images', '1,430', '780', '2,210'],
    ['Train (70%)', '1,001', '546', '1,547'],
    ['Validation (15%)', '214', '117', '331'],
    ['Test (15%)', '215', '117', '332']]))
A('<p>The split is stratified (random seed 42) and unreadable images are removed first. Label 0 = genuine, '
  '1 = fake. How the fake photos were produced is <i>not recorded</i> in the notebook. These two folders are not on '
  'this computer; the figures above are from the notebook output.</p>')
A('<p><b>(b) Roboflow "Fake Currency Detection" v2 (multiclass)</b>, stored in the data folder:</p>')
A(kv([
    ['Size', '3,626 images (train 2,538, validation 725, test 363)'],
    ['Labels', 'Multi-class classification file <code>_classes.csv</code> with columns fake / real'],
    ['Class balance', '3,621 real and only <b>5 fake</b> (train 3, validation 0, test 2)'],
    ['Preprocessing', 'Auto-orient, resize 640 &times; 640 (stretch); no augmentation'],
    ['Use', 'Not used to train any bundled model: with 5 fake photos it cannot teach a fake detector']]))
A('<p><b>(c) FCDS_Dataset</b>: two folders of 14 photos each (28 JPG images); too small to train on.</p>')
A('<p><b>(d) Synthetic altered notes</b>: made in the Rs 5,000 notebook (section 3.2). Altered photos are used as '
  'the "fake" side of the Rs 5,000 classifiers.</p>')

# ------------------------------------------------------------------ 3
A('<h2>3. Notebooks, step by step</h2>')
A('<h3>3.1 <code>New_Trained_Yolo-v11small.ipynb</code>: trains the YOLO11s detector (6 cells)</h3>')
A(table(['Cell', 'What it does'], [
    ['0', 'Installs ultralytics and roboflow.'],
    ['1', 'Asks for the Roboflow API key, downloads project <i>currency-security-features</i> version 8 in YOLOv11 format.'],
    ['2', 'Reads <code>data.yaml</code>: 13 classes, prints the class names.'],
    ['3', 'Trains: <code>YOLO("yolo11s.pt").train(...)</code> with the settings below (outputs show the dataset scan).'],
    ['4', 'Validates the best weights on the validation set (per-class table).'],
    ['5', 'Evaluates <code>best.pt</code> on the test split and prints mAP50, mAP50-95 and per-class mAP50.']]))
A(kv([
    ['Starting weights', 'yolo11s.pt (COCO pretrained), 9,417,831 parameters, 21.4 GFLOPs (fused)'],
    ['Settings', 'epochs 100, image size 640, batch -1 (automatic), patience 20, optimiser AdamW, lr0 0.001, '
                 'weight decay 0.0005, cosine learning rate, workers 2, seed 42, device GPU'],
    ['Hardware / time', 'Google Colab, Tesla T4; 100 epochs finished in 2.527 hours; Ultralytics 8.4.190'],
    ['Output', 'best.pt and last.pt (19.2 MB each) in <code>YOLO11s_currency_training/currency_security_v8/train</code>']]))
A('<p><b>Validation result</b> (705 images, 2,655 boxes): precision 0.975, recall 0.975, mAP50 0.980, '
  'mAP50-95 0.876. <b>Test result</b> (348 images, 1,354 boxes): precision 0.968, recall 0.980, mAP50 <b>0.980</b>, '
  'mAP50-95 <b>0.872</b>; inference 14.0 ms per image on the T4.</p>')
A(table(['Class (test split)', 'Images', 'Precision', 'Recall', 'mAP50', 'mAP50-95'], [
    ['1000Rs Note', '42', '0.966', '1.000', '0.990', '0.980'], ['100Rs Note', '46', '0.969', '1.000', '0.992', '0.988'],
    ['10Rs Note', '41', '0.987', '1.000', '0.995', '0.985'], ['20Rs Note', '61', '0.966', '1.000', '0.995', '0.995'],
    ['5000Rs Note', '43', '1.000', '0.982', '0.995', '0.963'], ['500Rs Note', '60', '0.964', '1.000', '0.977', '0.977'],
    ['50Rs Note', '51', '0.990', '0.980', '0.985', '0.985'], ['printed_year', '112', '0.997', '1.000', '0.995', '0.716'],
    ['sbp_seal', '245', '0.987', '0.994', '0.994', '0.878'], ['security_dots', '51', '1.000', '0.996', '0.995', '0.800'],
    ['security_lines', '57', '0.927', '0.965', '0.948', '0.771'], ['security_thread', '81', '0.838', '0.833', '0.888', '0.439'],
    ['serial_number', '175', '0.993', '0.996', '0.995', '0.862']]))
A('<p>The weakest class is <code>security_thread</code> (mAP50 0.888, mAP50-95 0.439): the thin thread is hard '
  'to box tightly. This is why the app checks the thread by count and never relies on a single detection.</p>')

A('<h3>3.2 <code>CNN_Model_5000pkr.ipynb</code>: Rs 5,000 data preparation and patch experiments (63 cells)</h3>')
A(table(['Cells', 'What it does'], [
    ['0-8', 'Mounts Google Drive, lists the seven denomination folders and counts the photos (3,577), checks each '
            'denomination has at least 200 photos.'],
    ['9-14', 'Defines the safe area (12% border cut off), the 8 &times; 4 patch grid (32 patches), and the alteration '
             'functions: local blur, noise, brightness, contrast, colour shift, noise texture, partial obstruction '
             '(altering 30-55% of one patch). Generates <b>200 altered images per denomination = 1,400</b> '
             '(seed 42) and writes <code>altered_images_metadata.csv</code> (denomination, patch, alteration).'],
    ['15-34', 'Checks patch counts, shows original/altered side-by-side, and tests a second alteration set '
              '(pixelation, brightness, contrast, colour shift, noise, texture disruption, heavy blur).'],
    ['35-40', 'Rebuilds the folder setup after a Colab restart and generates / visually inspects the altered set.'],
    ['41-47', 'Tests the Roboflow-hosted YOLO11s workflow: finds the note box, detects corners with Hough lines '
              '(border-constrained), normalises the box and cuts the 8 &times; 4 grid.'],
    ['48-51', 'Patch comparison: MobileNetV3-Large (ImageNet, 960-value embedding per patch) on 32 patches of the '
              'original and altered image; cosine distance per patch; full run on all 1,400 pairs.'],
    ['52-56', 'Builds a bank of genuine reference embeddings and scores genuine vs genuine and altered vs genuine; '
              'ROC and best-threshold analysis.'],
    ['57-62', 'Paired MobileNetV3-Large consistency experiment (genuine vs genuine and original vs altered), saved '
              'results (<code>mobilenet_patch_results_1400.csv</code>) and distance statistics.']]))
A('<p><b>Outcome of the patch-distance experiment</b> (step 15: 140 genuine vs 1,400 altered): ROC AUC 0.583 '
  '(largest patch distance), 0.576 (average) and 0.574 (median). Distance between patch embeddings separated '
  'genuine from altered only weakly, so the app uses a trained classifier on the note instead (3.4).</p>')

A('<h3>3.3 <code>MNV3small_model_on_6currency_pkr_with_extended_evaluation_v2.ipynb</code>: MobileNetV3-Small (33 cells)</h3>')
A(table(['Cells', 'What it does'], [
    ['0-1', 'Reads the Genuine and Fake folders (1,430 + 780 = 2,210), removes unreadable images, makes the 70/15/15 '
            'stratified split and saves the split CSV files.'],
    ['2', 'Builds the tf.data pipelines: decode, resize to 224 &times; 224, batch 32; training-only augmentation: '
          'RandomRotation 0.025, RandomTranslation 0.04, RandomZoom 0.08, RandomContrast 0.10 (no flips).'],
    ['3', 'Model and frozen-backbone training (below).'],
    ['4-5', 'Fine-tunes the last 30 layers; compares validation accuracy and selects the final model.'],
    ['6-9', 'Test evaluation: confusion matrix, classification report, ROC AUC; saves the training summary JSON.'],
    ['10-11', 'Converts the selected model to a float32 TensorFlow Lite file and tests one batch.'],
    ['12-15', 'Downloads / saves the files to Drive.'],
    ['16-20', 'Extended evaluation: confusion matrix, ROC and precision-recall curves, threshold analysis, '
              'per-image predictions, most confident errors, misclassified-image gallery.'],
    ['21-27', 'Loads the TFLite model, evaluates it on the same test set, checks Keras vs TFLite agreement and '
              'measures inference latency.'],
    ['28-33', 'Saves the consolidated evaluation report and CSV files.']]))
A(kv([
    ['Model', 'MobileNetV3Small (ImageNet weights, <code>include_preprocessing=True</code>) &rarr; global average '
              'pooling &rarr; Dropout 0.30 &rarr; Dense(1, sigmoid) named <code>fake_probability</code>'],
    ['Stage 1 (frozen)', 'Backbone frozen; Adam lr 1e-3; binary cross-entropy; balanced class weights '
                         '{genuine 0.773, fake 1.417}; up to 20 epochs; early stopping (patience 5) and '
                         'learning-rate reduction on validation loss'],
    ['Stage 2 (fine-tune)', 'Last 30 layers unfrozen (batch-norm kept frozen); Adam lr 1e-5; up to 12 epochs'],
    ['Selection', 'Frozen and fine-tuned tied at validation accuracy 0.9698; the <b>frozen</b> model was kept'],
    ['Test result (332 images)', 'Accuracy <b>0.9669</b>, ROC AUC <b>0.9961</b>. Confusion matrix [[210, 5], [6, 111]]: '
                                 'genuine precision 0.9722 / recall 0.9767; fake precision 0.9569 / recall 0.9487'],
    ['Threshold', '0.50 (initial, not tuned)']]))

A('<h3>3.4 Rs 5,000 classifiers: what the project files record</h3>')
A('<p><b>Alteration classifier</b> (<code>rs5000_mobilenetv3large.tflite</code>): MobileNetV3-Large, trained on genuine '
  'Rs 5,000 photos versus synthetic alterations from 3.2. Recorded split: train 326 genuine + 325 altered, '
  'validation 70 + 70, test 71 genuine + 70 altered (141). Input 224 &times; 224 RGB float32 0-255 (the model '
  'rescales itself with <code>Rescaling(1/127.5, offset -1)</code>); output <code>altered_probability</code>.</p>')
A(table(['Test metric (141 images)', 'Value'], [
    ['Accuracy', '0.9433'], ['Precision', '0.9559'], ['Recall', '0.9286'], ['F1', '0.9420'], ['ROC AUC', '0.9885'],
    ['Confusion matrix', '[[68, 3], [5, 65]]']], 'narrow'))
A('<p>Not recorded: epoch count, optimiser, learning rate, batch size and augmentation of this run. A manual test '
  'showed a limit: an image with the security dots erased scored 0.005 (genuine-like), so the app never trusts this '
  'score alone.</p>')
A('<p><b>Genuine / counterfeit classifier</b> (<code>mobilenetv3_pkr5000_counterfeit.tflite</code>): a PyTorch '
  'torchvision MobileNetV3-Large with a 2-way head (checkpoint <code>mobilenetv3_pkr5000.pth</code>, classes '
  '<code>counterfeit = 0, genuine = 1</code>, 224 px, ImageNet mean/std). It was converted PyTorch &rarr; ONNX '
  '&rarr; onnx2tf (float32) with the normalisation and softmax built into the graph, and checked against PyTorch: '
  'largest probability difference 2.4e-7, same class on 8 of 8 test inputs. The training notebook and test metrics '
  'for this checkpoint were not among the provided files (<i>not recorded</i>).</p>')

A('<h3>3.5 Monument classifier (MobileNetV2): <code>tools/train_monument.py</code></h3>')
A(kv([
    ['Data', 'DataSet_sorted (section 2.2): 7 monument classes + invalid'],
    ['Model', 'MobileNetV2 (ImageNet) with a new 8-class head'],
    ['Input', 'The whole image letterboxed on grey 114 into 224 &times; 224; pixels scaled x / 127.5 - 1 (the app '
              'reads <code>"preprocess": "letterbox"</code> from <code>monument_model_info.json</code>)'],
    ['Training', '12 epochs training the head, then 6 epochs fine-tuning the backbone; augmented copies of each '
                 'training photo; seed 7; trained on 2026-11-01'],
    ['Held-out test (recorded)', 'Each monument class 100% (33-50 test photos each); "invalid" 98.5% on 339 test photos'],
    ['Labels', 'monument_10, monument_20, monument_50, monument_100, monument_500, monument_1000, monument_5000, invalid'],
    ['Monuments', 'Rs 100: Ziarat Residency, Rs 5,000: Faisal Mosque (and one monument per other value)'],
    ['10-fold cross-validation', 'Mean accuracy 99.68%, std 0.30% (see the separate cross-validation report)']]))

# ------------------------------------------------------------------ 4
A('<h2>4. Integration into the app</h2>')
A('<h3>4.1 Architecture</h3>')
A('<p>The app is written in Flutter (Dart) and runs <b>entirely on the phone</b>. TensorFlow Lite models are run '
  'with the <code>tflite_flutter</code> package, text is read with Google ML Kit, and state is handled with '
  'Riverpod. The code is split in three layers inside <code>lib/features</code>:</p>')
A(table(['Layer', 'Folder', 'Role'], [
    ['Capture (scanner)', 'scanner/', 'Takes the photos of both sides, checks the side, review screen, manual Enhance switch'],
    ['Evidence collector', 'verification/data/on_device/', 'Runs the models and ML Kit; produces raw evidence only'],
    ['Decision engine', 'verification/domain/', 'Applies the note rules and the weighted score; produces REAL or FAKE'],
    ['Screens', 'verification/presentation/', 'Analysing screen and result screen (verdict, security-feature list, scanned images)']]))
A('<p>One principle runs through the design: <b>each model keeps one job and no model decides alone</b>. '
  'The repository (<code>on_device_currency_verification_repository.dart</code>) collects evidence; the '
  '<code>VerificationEngine</code> decides.</p>')

A('<h3>4.2 Step-by-step flow of one scan</h3>')
A(table(['Step', 'What happens', 'Model / tool'], [
    ['1', 'User captures the front: ML Kit document scanner (base mode, no filters), plain camera or gallery. '
          'Photos are never enhanced automatically; an optional Enhance switch on the review screen makes an '
          'enhanced copy only when turned on.', 'ML Kit Document Scanner'],
    ['2', 'Right after each photo the app checks it is a banknote and the right side (front vs back, same '
          'denomination). A wrong side is rejected with a message and the photo is dropped.', 'YOLO11s + monument classifier'],
    ['3', 'User captures the back; review screen shows both photos.', '-'],
    ['4', 'YOLO11s runs on each side: letterbox to 640 &times; 640, decode 8,400 candidates, non-maximum suppression '
          '(confidence 0.25, overlap 0.7), map boxes back to the photo.', 'YOLO11s'],
    ['5', 'Gates: is it really a whole note (shape and presence checks); denomination must agree on both sides.', 'YOLO output'],
    ['6', 'Both front serial numbers and the printed year are cut out using the YOLO boxes and read twice '
          '(plain crop and an enhanced crop for reading).', 'ML Kit Text Recognition'],
    ['7', 'Security dots and lines are counted inside their YOLO boxes by pixel analysis on the original photo.', 'Image analysis'],
    ['8', 'Rs 5,000 only: full-resolution inputs, edge microprint reading, alteration score and genuine/counterfeit score.',
          'MobileNetV3-Large &times; 2'],
    ['9', 'Monument on the back is classified and compared with the denomination.', 'MobileNetV2'],
    ['10', 'Evidence goes to the rule engine; the result screen shows the verdict, then the security-feature list, '
           'then the scanned images.', 'VerificationEngine']]))

A('<h3>4.3 Integrating each model</h3>')
A('<p><b>YOLO11s.</b> Exported from <code>best.pt</code> to TFLite (36.2 MB). Input float32, channels-first '
  '[1, 3, 640, 640], RGB 0-1, letterboxed on grey (Ultralytics style); output [1, 17, 8400] = 4 box values + 13 class '
  'scores for 8,400 candidates, with box coordinates divided by the input size. The class IDs are fixed and covered '
  'by a unit test:</p>')
A(table(['ID', 'Class', 'ID', 'Class', 'ID', 'Class'], [
    ['0', '1000Rs Note', '5', '500Rs Note', '10', 'security_lines'], ['1', '100Rs Note', '6', '50Rs Note', '11', 'security_thread'],
    ['2', '10Rs Note', '7', 'printed_year', '12', 'serial_number'], ['3', '20Rs Note', '8', 'sbp_seal', '', ''],
    ['4', '5000Rs Note', '9', 'security_dots', '', '']], 'narrow'))
A('<p>It runs in a background isolate so the screen never freezes. A detection counts as <i>confirmed</i> at '
  'confidence 0.50 or more; lower ones (down to 0.10) are only "faintly seen" and make a check unclear, not failed.</p>')
A('<p><b>Rs 5,000 alteration CNN.</b> Input [1, 224, 224, 3] float32 0-255 (the model rescales itself), output '
  '[1, 1] altered probability. <b>Rs 5,000 genuine/counterfeit CNN.</b> Input [1, 224, 224, 3] RGB 0-255 resized '
  'like torchvision, output [1, 2] probabilities in the order counterfeit, genuine. Both run only when YOLO '
  'finds Rs 5,000 on both sides, and both are supporting evidence only.</p>')
A('<p><b>Monument classifier.</b> Input [1, 224, 224, 3]: the whole back photo letterboxed on grey 114 and scaled '
  'x / 127.5 - 1; output 8 probabilities. The labels come from <code>monument_labels.txt</code> and the '
  'preprocessing from <code>monument_model_info.json</code>, so the model can be replaced without code changes. '
  'A prediction counts only at 0.60 or more confidence; a wrong monument or "invalid" at that confidence makes the '
  'note FAKE; below it the app asks for a clearer photo.</p>')
A('<p><b>MobileNetV3-Small.</b> Wired in the same way (224 &times; 224, 0-255, one sigmoid output named '
  '<code>fake_probability</code>, threshold 0.50, Rs 10-1,000 only) but switched off by the constant '
  '<code>kSmallCnnEnabled</code>.</p>')

A('<h3>4.4 The rule engine and the verdict</h3>')
A('<p>The engine checks each feature, gives it a weight, and combines them into a 0-100 score. The verdict is only '
  '<b>REAL</b> or <b>FAKE</b>: any failed feature makes the note FAKE; only a photo that cannot be judged is shown '
  'as UNABLE TO VERIFY, INCOMPLETE or NOT A BANKNOTE.</p>')
A(table(['Check', 'Weight', 'Rule'], [
    ['Denomination', '20', 'Read confidently and the same on both sides'],
    ['Serial numbers', '25', 'Two serials read, identical, and random: repeated digits (000000000) or patterns '
                             '(1234567890, alternating digits) are FAKE'],
    ['SBP seals', '15', '1 seal on the front, 3 on the back'],
    ['Dots / lines', '15', 'Exactly Rs 10: none, Rs 20: 1 line, Rs 50: 2 lines, Rs 100: 3 lines, Rs 500: 1 dot, '
                           'Rs 1,000: 2 dots, Rs 5,000: 3 dots; fewer, more or the wrong type = FAKE'],
    ['Security thread', '10', 'Exactly one on Rs 100, 500, 1,000, 5,000; none on Rs 10, 20, 50'],
    ['Printed year', '5', 'A valid year (1947 or later)'],
    ['Monument', '20', 'The monument on the back matches the denomination (confidence 0.60 or more)'],
    ['Surface anomaly', '10', 'Rs 5,000 alteration score is low'],
    ['Genuine/counterfeit CNN', '10', 'Rs 5,000 classifier says genuine'],
    ['Microprint', '5', 'Rs 5,000 edge microprint found at least 3 times']]))
A('<p>A failed critical feature multiplies the score by 0.45 (capped at 39); any other failure multiplies by 0.7 '
  'per failure (capped at 84). A score of 85 or more with no failure is REAL; everything else is FAKE. A good CNN '
  'score can never hide a missing feature.</p>')

A('<h3>4.5 Building and delivering</h3>')
A(kv([
    ['Android', 'GitHub Actions workflow <code>build_apk.yml</code> (Flutter stable, JDK 21) or <code>flutter build apk '
                '--release --split-per-abi</code> locally; arm64 build is about 110 MB'],
    ['iPhone', 'Workflow <code>build_ios.yml</code> on a GitHub macOS machine builds an unsigned .ipa (iOS 16 or newer, '
               'ML Kit needs it); installed with AltStore or Sideloadly using an Apple ID. The document scanner is Android-only, '
               'so iPhone uses the normal camera'],
    ['Tests', 'More than 200 automated tests run on every build (rules, serial pattern, exact dots/lines counts, '
              'monument check, side check, Enhance switch)'],
    ['Models in the repository', 'The five .tflite files are tracked through an exception in <code>.gitignore</code>']]))

css = ('<style>@page{margin:16mm}body{font-family:Arial,sans-serif;font-size:10pt;color:#222;line-height:1.35}'
       'h1{color:#1F3A5F;font-size:22pt;margin-bottom:2px}h2{color:#1F3A5F;border-bottom:2px solid #1F3A5F;'
       'padding-bottom:2px;margin-top:22px;page-break-after:avoid}h3{color:#1F3A5F;margin-bottom:4px;'
       'page-break-after:avoid}.sub{color:#555;margin-top:0}'
       'table{border-collapse:collapse;width:100%;font-size:8.5pt;margin:6px 0 10px;page-break-inside:auto}'
       'tr{page-break-inside:avoid}th{background:#1F3A5F;color:#fff;padding:4px 5px;text-align:left}'
       'td{border:1px solid #999;padding:3px 5px;vertical-align:top}tr:nth-child(even) td{background:#EEF2F7}'
       'table.narrow{width:60%}code{background:#f2f2f2;font-size:8.5pt}</style>')

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    base = os.path.join(a.out, 'Datasets_Notebooks_Models_Integration')
    open(base + '.html', 'w', encoding='utf8').write(
        '<html><head><meta charset="utf-8"><title>Datasets, Notebooks, Models and Integration</title>' + css +
        '</head><body>' + '\n'.join(H) + '</body></html>')
    edge = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
    subprocess.run([edge, '--headless', '--disable-gpu', f'--print-to-pdf={base}.pdf', '--no-pdf-header-footer',
                    base + '.html'], capture_output=True)
    print('PDF written:', os.path.exists(base + '.pdf'))
