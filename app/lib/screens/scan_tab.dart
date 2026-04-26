import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../widgets/scanner_overlay.dart';
import '../widgets/camera_controls_bar.dart';
import '../services/image_picker_service.dart';
import '../services/image_preprocessing_service.dart';
import 'dart:typed_data';
class ScanTab extends StatefulWidget {
  const ScanTab({super.key});

  @override
  State<ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends State<ScanTab> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  
  bool _isInit = false;
  bool _isFlashOn = false;

  bool _isProcessing = false;
  Uint8List? _capturedImageBytes;

  final ImagePickerService _imagePickerService = ImagePickerService();
  final ImagePreprocessingService _preprocessingService = ImagePreprocessingService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        // Prioritize back camera for a proper scanning experience
        final backCamera = _cameras!.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => _cameras![0],
        );

        _cameraController = CameraController(
          backCamera,
          ResolutionPreset.high,
          enableAudio: false,
        );
        
        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isInit = true;
          });
        }
      }
    } catch (e) {
      debugPrint("Camera initialization error: $e");
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    // Deep hardware cleanup: Avoid camera memory leaks and crashes if the app gets backgrounded
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _cameraController?.dispose();
      setState(() {
        _isInit = false;
      });
    } else if (state == AppLifecycleState.resumed) {
      // Reboot camera on foreground
      if (_cameraController != null) {
        _initCamera();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // UX Performance Bug Fix: Pause background camera streaming when user navigates 
    // to Dashboard or History tabs (since IndexedStack keeps tabs mounted under Offstage).
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      final bool isVisible = TickerMode.of(context);
      if (isVisible) {
        _cameraController!.resumePreview().catchError((_) {});
      } else {
        _cameraController!.pausePreview().catchError((_) {});
      }
    }
  }

  Future<void> _toggleFlash() async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      final newFlashState = !_isFlashOn;
      await _cameraController!.setFlashMode(
        newFlashState ? FlashMode.torch : FlashMode.off,
      );
      setState(() {
        _isFlashOn = newFlashState;
      });
    }
  }

  Future<void> _takePicture() async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      if (_cameraController!.value.isTakingPicture || _isProcessing) return;
      
      setState(() => _isProcessing = true);
      try {
        final XFile file = await _cameraController!.takePicture();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Processing Camera Image...'), duration: Duration(milliseconds: 1000)),
          );
        }

        final Uint8List? processedBytes = await _preprocessingService.processImageForAI(file);
        
        if (mounted) {
          if (processedBytes != null) {
            setState(() {
              _capturedImageBytes = processedBytes;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Image captured and tensor optimized! Ready for AI.'), backgroundColor: Colors.green),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to process image.'), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        debugPrint("Error taking picture: $e");
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _pickFromGallery() async {
    final XFile? image = await _imagePickerService.pickImageFromGallery();
    if (image != null) {
      setState(() => _isProcessing = true);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Processing Gallery Image...'), duration: Duration(milliseconds: 1000)),
        );
      }

      final Uint8List? processedBytes = await _preprocessingService.processImageForAI(image);
      
      if (mounted) {
        if (processedBytes != null) {
          setState(() {
            _capturedImageBytes = processedBytes;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gallery Image mapped and optimized! Ready for AI.'), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to process gallery image.'), backgroundColor: Colors.red),
          );
        }
      }
      
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInit || _cameraController == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Live Camera Feed
          CameraPreview(_cameraController!),

          // 2. Alignment Frame Component
          ScannerOverlay(
            width: 290,
            height: 155,
            borderColor: Theme.of(context).colorScheme.primary,
          ),

          // 3. User Controls Component
          CameraControlsBar(
            isFlashOn: _isFlashOn,
            onGalleryTap: _pickFromGallery,
            onShutterTap: _takePicture,
            onFlashToggle: _toggleFlash,
          ),
          
          // 4. Processing Overlay
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.cyan),
              ),
            ),
            
          // 5. Captured State Overlay
          if (_capturedImageBytes != null)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.85),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, color: Colors.greenAccent, size: 80),
                    const SizedBox(height: 20),
                    const Text("IMAGE TAKEN", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2)),
                    const SizedBox(height: 10),
                    const Text("Optimized and ready for AI analysis", style: TextStyle(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 30),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.cyan, width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(_capturedImageBytes!, width: 224, height: 224, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(height: 40),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white24,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      icon: const Icon(Icons.refresh),
                      label: const Text("Retake", style: TextStyle(fontSize: 16)),
                      onPressed: () => setState(() => _capturedImageBytes = null),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
