import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:light/light.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/haptics.dart';

/// Close-up camera for the Rs 5,000 microprint.
///
/// - guide box: put the line of tiny "5000" text inside it
/// - zoom slider 1×–3× (limited by what the lens supports)
/// - continuous auto-focus, re-focused on the guide box right before the
///   shot; tap anywhere to focus there
/// - torch switches on automatically below 50 lux (ambient light sensor),
///   or when the camera frame itself is dark on phones without a sensor
///
/// Pops with the photo path, or null when cancelled.
class MicroprintCameraScreen extends StatefulWidget {
  const MicroprintCameraScreen({super.key, this.expectedText = '5000'});

  /// The tiny text the user should look for. Only used in the on-screen
  /// hint; this screen does not read the text itself.
  final String expectedText;

  @override
  State<MicroprintCameraScreen> createState() => _MicroprintCameraScreenState();
}

/// State: owns the camera, zoom, torch and light-sensor logic.
/// WidgetsBindingObserver lets it release the camera when the app pauses.
class _MicroprintCameraScreenState extends State<MicroprintCameraScreen>
    with WidgetsBindingObserver {
  /// Ambient light below this (in lux) counts as dark, so torch turns on.
  static const double lowLightLux = 50;

  /// Mean frame brightness (0–255) treated as "dark" when no lux sensor.
  static const int lowLightFrameLuma = 60;

  CameraController? _controller; // null until the camera is ready
  String? _error; // shown instead of the preview if the camera fails
  double _zoom = 1, _minZoom = 1, _maxZoom = 1;
  bool _torch = false;
  // Once the user taps the torch button, auto-torch stops overriding it.
  bool _torchSetByUser = false;
  bool _capturing = false; // true while taking the photo
  int? _lux; // latest light-sensor reading (null if no sensor)
  StreamSubscription<int>? _luxSub;
  // Time of the last brightness check (limits how often we check).
  DateTime _lastFrameCheck = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  /// Opens the back camera at max resolution and sets focus and zoom.
  /// On failure it stores a message in [_error].
  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      await controller.setFocusMode(FocusMode.auto);
      // Zoom range is capped at 3x.
      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = (await controller.getMaxZoomLevel()).clamp(_minZoom, 3.0);
      // Start at 2×: lets the phone stay ~10 cm away, where most phone
      // cameras (also low-end) can still focus.
      _zoom = 2.0.clamp(_minZoom, _maxZoom);
      await controller.setZoomLevel(_zoom);
      // Screen was closed while the camera was starting: release it.
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      _startLightMonitoring();
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Camera unavailable: $e');
    }
  }

  /// Listens to the phone's light sensor and turns the torch on or off.
  /// If the sensor is missing or fails, falls back to frame brightness.
  void _startLightMonitoring() {
    try {
      _luxSub = Light().lightSensorStream.listen(
        (lux) {
          _lux = lux;
          if (mounted) setState(() {});
          _autoTorch(lux < lowLightLux);
        },
        onError: (Object _) => _useFrameBrightness(),
      );
    } on Object {
      _useFrameBrightness();
    }
  }

  /// Fallback when there is no ambient light sensor: mean of the Y plane.
  void _useFrameBrightness() {
    final c = _controller;
    if (c == null || c.value.isStreamingImages) return;
    c.startImageStream((frame) {
      // Check at most once every 700 ms to save battery.
      final now = DateTime.now();
      if (now.difference(_lastFrameCheck).inMilliseconds < 700) return;
      _lastFrameCheck = now;
      final y = frame.planes.first.bytes;
      var sum = 0, n = 0;
      // Sample every 97th pixel: fast, and enough for an average.
      for (var i = 0; i < y.length; i += 97) {
        sum += y[i];
        n++;
      }
      if (n > 0) _autoTorch(sum / n < lowLightFrameLuma);
    });
  }

  /// Switches the torch to match [dark], unless the user chose manually,
  /// nothing would change, or a photo is being taken.
  Future<void> _autoTorch(bool dark) async {
    if (_torchSetByUser || dark == _torch || _capturing) return;
    await _setTorch(dark);
  }

  /// Turns the torch on or off (errors are only logged).
  Future<void> _setTorch(bool on) async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torch = on);
    } on Object catch (e) {
      debugPrint('Torch unavailable: $e');
    }
  }

  /// Focuses and sets exposure at a point. [normalized] is x/y from 0 to 1
  /// (0,0 = top-left of the preview). Not all phones support this.
  Future<void> _focusAt(Offset normalized) async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.setFocusPoint(normalized);
      await c.setExposurePoint(normalized);
    } on Object catch (e) {
      debugPrint('Focus point not supported: $e');
    }
  }

  /// Takes the photo and closes the screen, returning the file path.
  /// On failure it shows a snackbar and lets the user try again.
  Future<void> _capture() async {
    final c = _controller;
    if (c == null || _capturing) return;
    setState(() => _capturing = true);
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
      // Re-focus on the guide box and give the lens a moment to settle.
      await _focusAt(const Offset(0.5, 0.5));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final shot = await c.takePicture();
      await Haptics.capture();
      if (mounted) Navigator.of(context).pop(shot.path);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
        setState(() => _capturing = false);
      }
    }
  }

  /// Frees the camera when the app goes inactive; reopens it on resume.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _init();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _luxSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      // Top bar: title and a manual torch button.
      appBar: AppBar(
        title: const Text('MICROPRINT CLOSE-UP'),
        actions: [
          IconButton(
            tooltip: 'Torch',
            icon: Icon(_torch ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                color: _torch ? AppColors.amber : null),
            onPressed: c == null
                ? null
                : () {
                    _torchSetByUser = true;
                    _setTorch(!_torch);
                  },
          ),
        ],
      ),
      // Body has 3 states: error text, loading spinner, or live camera.
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : c == null || !c.value.isInitialized
              ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
              : Column(
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) => GestureDetector(
                          onTapUp: (d) => _focusAt(Offset(
                            d.localPosition.dx / box.maxWidth,
                            d.localPosition.dy / box.maxHeight,
                          )),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Camera preview, filled to the screen. Width
                              // and height are swapped because the sensor
                              // is landscape but the phone is portrait.
                              ClipRect(
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: c.value.previewSize?.height ?? box.maxWidth,
                                    height: c.value.previewSize?.width ?? box.maxHeight,
                                    child: CameraPreview(c),
                                  ),
                                ),
                              ),
                              // Dimmed overlay with the guide box.
                              CustomPaint(painter: _GuidePainter()),
                              // Hint text at the top.
                              Positioned(
                                left: 16,
                                right: 16,
                                top: 16,
                                child: _Hint(expected: widget.expectedText, lux: _lux),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Zoom slider and shutter button.
                    _Controls(
                      zoom: _zoom,
                      min: _minZoom,
                      max: _maxZoom,
                      capturing: _capturing,
                      onZoom: (z) {
                        setState(() => _zoom = z);
                        c.setZoomLevel(z);
                      },
                      onCapture: _capture,
                    ),
                  ],
                ),
    );
  }
}

/// Instruction box over the preview (English). Also shows the
/// current light level in lux when a light sensor is available.
class _Hint extends StatelessWidget {
  const _Hint({required this.expected, required this.lux});

  final String expected;

  /// Light reading, or null when there is no sensor.
  final int? lux;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Put the tiny "$expected" text from the note\'s edge inside the box, '
        'about 10 cm away and steady. Tap the text to focus.'
        '${lux == null ? '' : '  ·  Light: $lux lux'}',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.35),
      ),
    );
  }
}

/// Bottom bar: zoom slider (min to max) and the round shutter button.
/// The button is disabled and shows a spinner while [capturing].
class _Controls extends StatelessWidget {
  const _Controls({
    required this.zoom,
    required this.min,
    required this.max,
    required this.capturing,
    required this.onZoom,
    required this.onCapture,
  });

  /// Current zoom and the allowed range.
  final double zoom, min, max;
  final bool capturing;
  final ValueChanged<double> onZoom;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.zoom_out_rounded, color: Colors.white70),
                Expanded(
                  child: Slider(
                    value: zoom.clamp(min, max),
                    min: min,
                    // If the lens cannot zoom, keep a tiny range so the
                    // slider is valid, and disable it (onChanged null).
                    max: max > min ? max : min + 0.01,
                    activeColor: AppColors.cyan,
                    onChanged: max > min ? onZoom : null,
                  ),
                ),
                Text('${zoom.toStringAsFixed(1)}×',
                    style: const TextStyle(color: Colors.white)),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 76,
              height: 76,
              child: ElevatedButton(
                onPressed: capturing ? null : onCapture,
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  backgroundColor: AppColors.cyan,
                  padding: EdgeInsets.zero,
                ),
                child: capturing
                    ? const CircularProgressIndicator(color: AppColors.onyx)
                    : const Icon(Icons.camera_alt_rounded,
                        color: AppColors.onyx, size: 32),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dims everything outside the guide box (centre 84% × 34%) and draws a
/// cyan border around the box.
class _GuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Box: 8% from each side, starting 33% down, 84% wide, 34% tall.
    final box = Rect.fromLTWH(
      size.width * 0.08,
      size.height * 0.33,
      size.width * 0.84,
      size.height * 0.34,
    );
    // Full-screen rectangle minus the box (even-odd) = dimmed frame.
    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(box, const Radius.circular(12)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.45));
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(12)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = AppColors.cyan,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
