/// Screen listing every saved scan (newest first) with a CSV export.
///
/// Reads the SQLite database through [scanHistoryDatabaseProvider]. Each row
/// shows the verdict, denomination, time and confidence; tapping a row opens
/// the status of every security feature, including the Quaid-e-Azam portrait
/// and the monument. The share button writes all scans to a CSV file and
/// opens the phone's share sheet (save to Drive, send by e-mail, ...).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/cyber_background.dart';
import '../../../core/widgets/glass_container.dart';
import '../data/scan_history_database.dart';
import '../data/scan_record.dart';

/// Human names of the features shown in the details sheet.
const Map<String, String> _featureNames = {
  'denomination': 'Denomination',
  'serialNumber': 'Serial numbers',
  'sbpSeals': 'SBP seals',
  'linesDots': 'Dots / lines',
  'securityThread': 'Security thread',
  'printedYear': 'Printed year',
  'portrait': 'Quaid-e-Azam portrait (front)',
  'monument': 'Monument (back)',
  'surfaceAnomaly': 'Surface check (Rs 5,000)',
  'counterfeitCnn': 'Genuine/counterfeit CNN (Rs 5,000)',
  'microprint': 'Microprint (Rs 5,000)',
};

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late Future<List<ScanRecord>> _records;

  @override
  void initState() {
    super.initState();
    _records = ref.read(scanHistoryDatabaseProvider).all();
  }

  void _reload() => setState(() {
        _records = ref.read(scanHistoryDatabaseProvider).all();
      });

  /// Writes every scan to a CSV file and opens the share sheet.
  Future<void> _exportCsv() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final csv = await ref.read(scanHistoryDatabaseProvider).exportCsv();
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'scan_history.csv'));
      // A byte-order mark makes Excel open the file as UTF-8.
      await file.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Scan history (CSV)',
      ));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not export: $e')));
    }
  }

  /// Asks, then deletes every saved scan.
  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all saved scans?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('DELETE')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(scanHistoryDatabaseProvider).clear();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('SCAN HISTORY'),
        actions: [
          IconButton(
            tooltip: 'Export all scans as CSV',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: _exportCsv,
          ),
          IconButton(
            tooltip: 'Delete all',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _clearAll,
          ),
        ],
      ),
      body: CyberBackground(
        child: SafeArea(
          child: FutureBuilder<List<ScanRecord>>(
            future: _records,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Could not read history: ${snap.error}'));
              }
              final list = snap.data ?? const [];
              if (list.isEmpty) {
                return const Center(
                  child: Text('No scans saved yet.\nEvery scan is saved here automatically.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary)),
                );
              }
              final real = list.where((r) => r.verdict == 'real').length;
              final fake = list.where((r) => r.verdict == 'fake').length;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '${list.length} scans  ·  $real real  ·  $fake fake',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  for (final r in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ScanTile(record: r, onTap: () => _showDetails(r)),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Bottom sheet with every feature status of one scan.
  void _showDetails(ScanRecord r) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${_verdictText(r.verdict)} · ${r.denomination == null ? 'Rs ?' : 'Rs ${r.denomination}'} · ${r.confidencePct}%',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(_formatTime(r.scannedAt),
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            for (final id in kRecordedFeatures)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(_statusIcon(r.features[id.name]),
                    color: _statusColor(r.features[id.name])),
                title: Text(_featureNames[id.name] ?? id.name),
                trailing: Text(_statusText(r.features[id.name]),
                    style: TextStyle(color: _statusColor(r.features[id.name]))),
              ),
            if (r.summary.isNotEmpty) ...[
              const Divider(),
              Text(r.summary,
                  style: const TextStyle(color: AppColors.textSecondary, height: 1.4)),
            ],
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () async {
                final id = r.id;
                if (id == null) return;
                Navigator.pop(context);
                await ref.read(scanHistoryDatabaseProvider).delete(id);
                _reload();
              },
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('DELETE THIS SCAN'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the history list.
class _ScanTile extends StatelessWidget {
  const _ScanTile({required this.record, required this.onTap});

  final ScanRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _verdictColor(record.verdict);
    final portrait = record.features['portrait'];
    final monument = record.features['monument'];
    return GestureDetector(
      onTap: onTap,
      child: GlassContainer(
        borderColor: color.withValues(alpha: 0.5),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_verdictText(record.verdict),
                  style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.denomination == null ? 'Rs ?' : 'Rs ${record.denomination}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  Text(_formatTime(record.scannedAt),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                    'Portrait: ${_statusText(portrait)}  ·  Monument: ${_statusText(monument)}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            Text('${record.confidencePct}%',
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w800, fontSize: 18)),
          ],
        ),
      ),
    );
  }
}

String _verdictText(String v) => switch (v) {
      'real' => 'REAL',
      'fake' => 'FAKE',
      'unableToVerify' => 'UNABLE',
      'incomplete' => 'INCOMPLETE',
      _ => v.toUpperCase(),
    };

Color _verdictColor(String v) => switch (v) {
      'real' => AppColors.emerald,
      'fake' => AppColors.crimson,
      _ => AppColors.amber,
    };

String _statusText(String? s) => switch (s) {
      'pass' => 'PASS',
      'fail' => 'FAIL',
      'warning' => 'WARNING',
      'inconclusive' => 'UNCLEAR',
      'skipped' => 'NOT CHECKED',
      'notApplicable' => 'N/A',
      _ => '-',
    };

Color _statusColor(String? s) => switch (s) {
      'pass' => AppColors.emerald,
      'fail' => AppColors.crimson,
      'warning' || 'inconclusive' => AppColors.amber,
      _ => AppColors.textMuted,
    };

IconData _statusIcon(String? s) => switch (s) {
      'pass' => Icons.check_circle_rounded,
      'fail' => Icons.cancel_rounded,
      'warning' || 'inconclusive' => Icons.help_rounded,
      _ => Icons.remove_circle_outline_rounded,
    };

String _formatTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}  ${two(t.hour)}:${two(t.minute)}';
}
