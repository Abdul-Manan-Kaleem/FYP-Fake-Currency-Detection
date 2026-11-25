"""Report (PDF) about the scan-history database.

    python build_database_report.py --out DIR
"""
import argparse
import os
import subprocess


def table(header, rows, cls=''):
    h = ''.join(f'<th>{c}</th>' for c in header)
    b = ''.join('<tr>' + ''.join(f'<td>{c}</td>' for c in r) + '</tr>' for r in rows)
    return f'<table class="{cls}"><thead><tr>{h}</tr></thead><tbody>{b}</tbody></table>'


H = []
A = H.append
A('<h1>Scan History Database</h1>')
A('<p class="sub">Local storage of every scan result &middot; Pakistani Currency Note Screening System &middot; '
  'Final Year Project, Riphah International University</p>')

A('<h2>1. Summary</h2>')
A('<p>Every time the app finishes checking a note, it saves the result automatically in a database on the phone. '
  'Nothing is typed by the user and nothing is sent over the internet. The saved scans can be browsed in the app '
  '(History screen) and exported as a CSV file that opens in Excel.</p>')
A(table(['Item', 'Detail'], [
    ['Storage type', 'SQLite database (a small database file inside the app)'],
    ['Flutter package', '<code>sqflite</code> 2.4.6 (with <code>path</code>, <code>path_provider</code>, <code>share_plus</code> for the export)'],
    ['Database file', '<code>scan_history.db</code> in the app\'s private storage (Android package <code>com.fyp.fake_currency_detector</code>)'],
    ['Table', '<code>scans</code>: one row per scan'],
    ['What is saved', 'Time, denomination, final result, confidence score, raw score, penalty, the result of each security feature (including the Quaid-e-Azam portrait and the monument), the reasons, and the full per-feature details'],
    ['When', 'Automatically, right after each result is produced (before it is shown)'],
    ['Export', 'CSV file (UTF-8, opens in Excel) through the phone\'s share sheet'],
    ['Online?', 'No. The data stays on the phone unless the user exports it']]))

A('<h2>2. Database or CSV: why a database</h2>')
A(table(['', 'SQLite database (used)', 'CSV file'], [
    ['Structure', 'Typed columns (number, text, date)', 'Everything is text'],
    ['Safe writes', 'A scan is saved completely or not at all (transaction)', 'A power cut or app kill while writing can leave a broken file'],
    ['Reading', 'Ask for one scan, the newest, only FAKE ones, counts per denomination', 'The whole file must be loaded and parsed'],
    ['Changing data', 'Delete or change one row', 'Rewrite the whole file'],
    ['Growth', 'Stays fast with thousands of rows', 'Gets slow and large'],
    ['On a phone', 'Made for apps; private to the app; no folder permissions', 'Needs a folder the user can find and write permission'],
    ['Opening outside the app', 'Needs a tool', 'Opens in Excel at once']]))
A('<p><b>Decision:</b> store in SQLite (reliable, queryable) and offer CSV only as an <i>export</i> for sharing and '
  'analysis. This gives the strengths of both.</p>')

A('<h2>3. Table <code>scans</code></h2>')
A(table(['Column', 'Type', 'Meaning'], [
    ['id', 'INTEGER, primary key, automatic', 'Row number of the scan'],
    ['scanned_at', 'TEXT (ISO date and time)', 'When the scan finished, e.g. 2026-11-26T10:15:42'],
    ['denomination', 'INTEGER', 'Note value in rupees (10, 20, 50, 100, 500, 1000, 5000), empty if not read'],
    ['verdict', 'TEXT', 'Final result: real, fake, unableToVerify, incomplete'],
    ['confidence_pct', 'INTEGER', 'The percentage shown to the user (0-100)'],
    ['raw_score', 'REAL', 'Score before penalties = points earned / total weight x 100'],
    ['penalty', 'TEXT', 'none, featureFailure or criticalFailure'],
    ['denomination_check', 'TEXT', 'Status of the denomination check'],
    ['serialNumber', 'TEXT', 'Status of the serial-number check'],
    ['sbpSeals', 'TEXT', 'Status of the SBP seals check'],
    ['linesDots', 'TEXT', 'Status of the dots / lines check'],
    ['securityThread', 'TEXT', 'Status of the security thread check'],
    ['printedYear', 'TEXT', 'Status of the printed-year check'],
    ['portrait', 'TEXT', 'Status of the <b>Quaid-e-Azam portrait</b> check (front)'],
    ['monument', 'TEXT', 'Status of the <b>monument</b> check (back)'],
    ['surfaceAnomaly', 'TEXT', 'Rs 5,000 alteration check'],
    ['counterfeitCnn', 'TEXT', 'Rs 5,000 genuine/counterfeit check'],
    ['microprint', 'TEXT', 'Rs 5,000 microprint check'],
    ['summary', 'TEXT', 'The reasons shown to the user, joined into one text'],
    ['details_json', 'TEXT (JSON)', 'Per feature: name, status, weight, points earned, one-line explanation']]))
A('<p>Each feature column holds one of: <code>pass</code>, <code>fail</code>, <code>warning</code>, '
  '<code>inconclusive</code>, <code>skipped</code> (not checked), <code>notApplicable</code>, or '
  '<code>notRun</code>. The denomination <i>check</i> is called <code>denomination_check</code> so it does not clash '
  'with the denomination <i>value</i> column (a bug a unit test caught during development).</p>')
A('<p><b>Illustrative example of one row</b> (shape only, not a real scan): <code>id 12 | 2026-11-26T10:15:42 | 100 | '
  'real | 96 | 96.4 | none | pass | pass | pass | pass | pass | pass | pass | pass | notApplicable | notApplicable | '
  'notApplicable | "All YOLO11s security features ... passed" | [...]</code></p>')

A('<h2>4. How a scan gets into the database</h2>')
A(table(['Step', 'What happens', 'Code'], [
    ['1', 'The rule engine produces the final result (verdict, score, list of checks)', '<code>verification_engine.dart:142</code> (<code>evaluate</code>)'],
    ['2', 'The controller saves it before showing the screen; a storage problem is only logged and never blocks the result', '<code>verification_controller.dart:125</code> (<code>saveScanQuietly</code>)'],
    ['3', 'The result is flattened to a <code>ScanRecord</code> (time, value, verdict, score, one status per feature)', '<code>scan_record.dart:81</code> (<code>fromResult</code>)'],
    ['4', 'The record is inserted as a new row in <code>scans</code>', '<code>scan_history_database.dart:59</code> (<code>save</code>)'],
    ['5', 'The History screen reads the rows back, newest first', '<code>scan_history_database.dart:65</code> (<code>all</code>), <code>history_screen.dart:40</code>']]))
A('<p>The database is created the first time a scan is saved (<code>scan_history_database.dart:39</code>, '
  '<code>CREATE TABLE</code>), version 1.</p>')

A('<h2>5. What the user sees</h2><ul>'
  '<li><b>History button</b> (clock icon, top right of the capture screen): <code>capture_screen.dart:127</code>.</li>'
  '<li><b>List</b> of scans, newest first: verdict, value, time, confidence, and the portrait and monument status; '
  'a summary line with totals (scans, real, fake).</li>'
  '<li><b>Tap a scan</b> to see every security feature with its status, the reasons, and a delete button.</li>'
  '<li><b>Share button</b>: writes all scans to <code>scan_history.csv</code> and opens the phone\'s share sheet '
  '(<code>history_screen.dart:61</code>). The file starts with a byte-order mark so Excel reads it as UTF-8.</li>'
  '<li><b>Delete all</b> with a confirmation question (<code>history_screen.dart:79</code>).</li></ul>')

A('<h2>6. CSV export</h2>')
A('<p>Built by <code>csv_export.dart:46</code> (<code>scansToCsv</code>), oldest scan first, so the file reads like '
  'a log. Cells with a comma, quote or line break are wrapped in quotes as the CSV standard (RFC 4180) requires. '
  'Columns: id, timestamp, denomination_rs, final_result, confidence_percent, raw_score_percent, penalty, then one '
  'column per security feature (same names as the table), and reasons.</p>')

A('<h2>7. Examples of questions the database can answer</h2>')
A('<pre>-- how many scans of each result\n'
  'SELECT verdict, COUNT(*) FROM scans GROUP BY verdict;\n\n'
  '-- average confidence of real notes\n'
  'SELECT AVG(confidence_pct) FROM scans WHERE verdict = \'real\';\n\n'
  '-- every note that failed the portrait or the monument check\n'
  'SELECT scanned_at, denomination, portrait, monument FROM scans\n'
  'WHERE portrait = \'fail\' OR monument = \'fail\';\n\n'
  '-- the five newest scans\n'
  'SELECT * FROM scans ORDER BY scanned_at DESC LIMIT 5;</pre>')
A('<p>On the phone these are run by the app\'s code; for analysis, export the CSV and use Excel or Python. '
  '(The database file is private to the app, so it cannot be opened from a file manager.)</p>')

A('<h2>8. Testing</h2>')
A('<p>Automated tests (<code>test/portrait_and_history_test.dart</code>) check that a record keeps the time, '
  'denomination, verdict, score and every feature status; that a record survives the trip to and from a database '
  'row; that CSV cells are escaped; and that the CSV header and each row have the same number of columns. The '
  'whole suite of 217 tests passes. The database file itself (creating, inserting, reading on a real phone) has '
  'not been run on a device in these tests, so check the History screen once on the phone.</p>')

A('<h2>9. Limits</h2><ul>'
  '<li>Data stays on one phone; there is no sync or account. Uninstalling the app deletes it.</li>'
  '<li>The photos themselves are not stored in the database, only the results.</li>'
  '<li>Scans are saved when the result is produced; a later change (for example a Rs 5,000 microprint '
  'close-up) is not saved as a second row.</li>'
  '<li>The History screen is not password protected.</li></ul>')

css = ('<style>@page{margin:16mm}body{font-family:Arial,sans-serif;font-size:10pt;color:#222;line-height:1.38}'
       'h1{color:#1F3A5F;font-size:22pt;margin-bottom:2px}h2{color:#1F3A5F;border-bottom:2px solid #1F3A5F;'
       'padding-bottom:2px;margin-top:20px;page-break-after:avoid}.sub{color:#555;margin-top:0}'
       'table{border-collapse:collapse;width:100%;font-size:8.8pt;margin:6px 0 10px}tr{page-break-inside:avoid}'
       'th{background:#1F3A5F;color:#fff;padding:4px 5px;text-align:left}'
       'td{border:1px solid #999;padding:3px 5px;vertical-align:top}tr:nth-child(even) td{background:#EEF2F7}'
       'code{background:#f2f2f2;font-size:8.4pt}pre{background:#f2f2f2;padding:6px;font-size:8.2pt}</style>')

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    base = os.path.join(a.out, 'Scan_History_Database_Report')
    open(base + '.html', 'w', encoding='utf8').write(
        '<html><head><meta charset="utf-8"><title>Scan History Database</title>' + css +
        '</head><body>' + '\n'.join(H) + '</body></html>')
    edge = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
    subprocess.run([edge, '--headless', '--disable-gpu', f'--print-to-pdf={base}.pdf', '--no-pdf-header-footer',
                    base + '.html'], capture_output=True)
    print('PDF written:', os.path.exists(base + '.pdf'))
