import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'dart:typed_data';
import 'dart:io';
import 'processing_screen.dart';

class ScanTab extends StatefulWidget {
  const ScanTab({super.key});

  @override
  State<ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends State<ScanTab> {
  bool _isProcessing = false;
  Uint8List? _frontImageBytes;
  Uint8List? _backImageBytes;

  Future<void> _startScanner() async {
    setState(() => _isProcessing = true);
    try {
      final options = DocumentScannerOptions(
        documentFormats: const {DocumentFormat.jpeg},
        mode: ScannerMode.filter,
        pageLimit: 2,
        isGalleryImport: true,
      );
      
      final documentScanner = DocumentScanner(options: options);
      final DocumentScanningResult? result = await documentScanner.scanDocument();

      if (result != null && result.images != null && result.images!.isNotEmpty) {
        if (result.images!.length == 2) {
          final frontBytes = await File(result.images![0]).readAsBytes();
          final backBytes = await File(result.images![1]).readAsBytes();
          
          if (mounted) {
            setState(() {
              _frontImageBytes = frontBytes;
              _backImageBytes = backBytes;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Both sides successfully captured!'), backgroundColor: Colors.green),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please scan exactly 2 pages (Front and Back).'), backgroundColor: Colors.orange),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Scanner error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scanner error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _frontImageBytes != null && _backImageBytes != null
            ? _buildResultsView()
            : _buildStartView(),
      ),
    );
  }

  Widget _buildStartView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.document_scanner, size: 80, color: Colors.cyan),
          const SizedBox(height: 24),
          const Text(
            "Scan Currency Note",
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              "Our smart scanner will automatically detect edges and crop the note for you. Please scan both the Front and Back of the note in one go.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ),
          const SizedBox(height: 40),
          _isProcessing
              ? const CircularProgressIndicator(color: Colors.cyan)
              : ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text("Open Scanner"),
                  onPressed: _startScanner,
                ),
        ],
      ),
    );
  }

  Widget _buildResultsView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle_outline_rounded, color: Colors.greenAccent, size: 80),
        const SizedBox(height: 20),
        const Text("IMAGES TAKEN", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(height: 10),
        const Text("Both sides optimized and ready for AI analysis", style: TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildImageThumb(_frontImageBytes!),
            const SizedBox(width: 16),
            _buildImageThumb(_backImageBytes!),
          ],
        ),
        const SizedBox(height: 40),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white24,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              icon: const Icon(Icons.refresh),
              label: const Text("Retake All", style: TextStyle(fontSize: 16)),
              onPressed: () => setState(() {
                _frontImageBytes = null;
                _backImageBytes = null;
              }),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              icon: const Icon(Icons.analytics),
              label: const Text("Analyze AI", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProcessingScreen(
                      frontImageBytes: _frontImageBytes!,
                      backImageBytes: _backImageBytes!,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildImageThumb(Uint8List bytes) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.cyan, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(bytes, width: 140, height: 140, fit: BoxFit.cover),
      ),
    );
  }
}
