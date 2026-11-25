/// Local SQLite database that keeps every scan result on the phone.
///
/// One table, `scans`: one row per scan with the time, denomination, final
/// result, confidence score, the status of each security feature and the full
/// per-feature details as JSON. The database lives in the app's private
/// storage and survives restarts. It never leaves the phone unless the user
/// exports it as CSV.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../verification/data/models/verification_result_model.dart';
import '../domain/csv_export.dart';
import 'scan_record.dart';

/// Opens the database lazily and offers save / read / delete / export.
class ScanHistoryDatabase {
  Database? _db;

  static const String _table = 'scans';

  /// Opens (and on first use creates) the database file.
  Future<Database> _open() async {
    final existing = _db;
    if (existing != null) return existing;
    final path = p.join(await getDatabasesPath(), 'scan_history.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // One TEXT column per security feature, so the table can be read
        // directly (for example in "DB Browser for SQLite").
        final featureColumns =
            kRecordedFeatures.map((f) => '${columnOf(f)} TEXT NOT NULL').join(', ');
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            scanned_at TEXT NOT NULL,
            denomination INTEGER,
            verdict TEXT NOT NULL,
            confidence_pct INTEGER NOT NULL,
            raw_score REAL NOT NULL,
            penalty TEXT NOT NULL,
            $featureColumns,
            summary TEXT,
            details_json TEXT
          )
        ''');
      },
    );
    _db = db;
    return db;
  }

  /// Saves one finished result. Returns the new row id.
  Future<int> save(VerificationResultModel result) async {
    final db = await _open();
    return db.insert(_table, ScanRecord.fromResult(result).toMap());
  }

  /// All saved scans, newest first.
  Future<List<ScanRecord>> all() async {
    final db = await _open();
    final rows = await db.query(_table, orderBy: 'scanned_at DESC, id DESC');
    return [for (final r in rows) ScanRecord.fromMap(r)];
  }

  /// Number of saved scans.
  Future<int> count() async {
    final db = await _open();
    return Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $_table')) ??
        0;
  }

  /// Deletes one scan.
  Future<void> delete(int id) async {
    final db = await _open();
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes every saved scan.
  Future<void> clear() async {
    final db = await _open();
    await db.delete(_table);
  }

  /// All scans as CSV text (see [scansToCsv]), oldest first, so the file
  /// reads like a log.
  Future<String> exportCsv() async {
    final records = (await all()).reversed;
    return scansToCsv(records);
  }

  /// Closes the database file.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

/// One shared database object for the whole app.
final scanHistoryDatabaseProvider = Provider<ScanHistoryDatabase>((ref) {
  final db = ScanHistoryDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Saves a result without ever disturbing the scan: a storage problem is only
/// logged, the user still sees the result.
Future<void> saveScanQuietly(
    ScanHistoryDatabase db, VerificationResultModel result) async {
  try {
    final id = await db.save(result);
    debugPrint('Scan saved to history (id $id)');
  } on Object catch (e) {
    debugPrint('Could not save scan to history: $e');
  }
}
