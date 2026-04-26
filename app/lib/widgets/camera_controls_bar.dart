import 'package:flutter/material.dart';

class CameraControlsBar extends StatelessWidget {
  final VoidCallback onGalleryTap;
  final VoidCallback onShutterTap;
  final VoidCallback onFlashToggle;
  final bool isFlashOn;

  const CameraControlsBar({
    super.key,
    required this.onGalleryTap,
    required this.onShutterTap,
    required this.onFlashToggle,
    required this.isFlashOn,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 40,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Gallery Upload Button
          IconButton(
            onPressed: onGalleryTap,
            icon: const Icon(Icons.photo_library, color: Colors.white, size: 36),
            tooltip: "Upload from Gallery",
          ),

          // Central Shutter Button
          GestureDetector(
            onTap: onShutterTap,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                color: Colors.white.withValues(alpha: 0.25),
              ),
              child: Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),

          // Flash Toggle Button
          IconButton(
            onPressed: onFlashToggle,
            icon: Icon(
              isFlashOn ? Icons.flash_on : Icons.flash_off,
              color: Colors.white,
              size: 36,
            ),
            tooltip: "Toggle Flash",
          ),
        ],
      ),
    );
  }
}
