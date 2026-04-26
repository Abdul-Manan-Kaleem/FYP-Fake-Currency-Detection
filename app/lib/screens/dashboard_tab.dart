import 'package:flutter/material.dart';
import '../models/scan_model.dart';

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  // Mock Data
  final List<ScanModel> recentScans = [
    ScanModel(id: 'SCN-8923', noteValue: 'Rs. 5000', isAuthentic: true, confidence: 0.98, date: DateTime.now().subtract(const Duration(minutes: 12))),
    ScanModel(id: 'SCN-8924', noteValue: 'Rs. 1000', isAuthentic: false, confidence: 0.12, date: DateTime.now().subtract(const Duration(hours: 2))),
    ScanModel(id: 'SCN-8925', noteValue: 'Rs. 500', isAuthentic: true, confidence: 0.94, date: DateTime.now().subtract(const Duration(days: 1))),
    ScanModel(id: 'SCN-8926', noteValue: 'Rs. 100', isAuthentic: true, confidence: 0.99, date: DateTime.now().subtract(const Duration(days: 2))),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Welcome back,', style: TextStyle(fontSize: 16, color: Colors.white.withValues(alpha: 0.6))),
                    const SizedBox(height: 4),
                    const Text('Abdul Manan', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  child: const Icon(Icons.person, size: 30, color: Colors.white),
                )
              ],
            ),
            const SizedBox(height: 40),

            // Monthly Statistics
            const Text('Monthly Statistics', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10)),
                ]
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem('Total', '142', Icons.document_scanner),
                  _buildStatItem('Authentic', '138', Icons.verified_user),
                  _buildStatItem('Fake', '4', Icons.warning_rounded, isAlert: true),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // Recent Scans
            const Text('Recent Scans', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 16),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recentScans.length,
              itemBuilder: (context, index) {
                final scan = recentScans[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scan.isAuthentic ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          scan.isAuthentic ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          color: scan.isAuthentic ? Colors.green : Colors.redAccent,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(scan.noteValue, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                            const SizedBox(height: 4),
                            Text(scan.id, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            scan.isAuthentic ? 'Authentic' : 'Counterfeit',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: scan.isAuthentic ? Colors.green : Colors.redAccent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('${(scan.confidence * 100).toInt()}% Confidence', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6))),
                        ],
                      )
                    ],
                  ),
                );
              },
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, {bool isAlert = false}) {
    return Column(
      children: [
        Icon(icon, color: isAlert ? Colors.white : Colors.white.withValues(alpha: 0.8), size: 28),
        const SizedBox(height: 12),
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
      ],
    );
  }
}
