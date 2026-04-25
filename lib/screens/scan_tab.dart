import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../widgets/scanner_overlay.dart';
import '../widgets/camera_controls_bar.dart';
import '../services/image_picker_service.dart';

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

  final ImagePickerService _imagePickerService = ImagePickerService();

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
      if (_cameraController!.value.isTakingPicture) return;
      try {
        final XFile file = await _cameraController!.takePicture();
        // TODO: Validate image data
        debugPrint("Picture taken: ${file.path}");
      } catch (e) {
        debugPrint("Error taking picture: $e");
      }
    }
  }

  Future<void> _pickFromGallery() async {
    final XFile? image = await _imagePickerService.pickImageFromGallery();
    if (image != null) {
      // TODO: Queue image to the model block
      debugPrint("Picked from gallery: ${image.path}");
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
        ],
      ),
    );
  }
}
