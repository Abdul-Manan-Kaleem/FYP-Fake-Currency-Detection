import 'package:flutter/material.dart';

class ScannerOverlay extends StatefulWidget {
  final double width;
  final double height;
  final Color borderColor;
  final Color laserColor;

  const ScannerOverlay({
    super.key,
    this.width = 290,
    this.height = 155,
    this.borderColor = Colors.blue, // Will use theme color generally
    this.laserColor = Colors.redAccent,
  });

  @override
  State<ScannerOverlay> createState() => _ScannerOverlayState();
}

class _ScannerOverlayState extends State<ScannerOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _laserAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // The frame height minus the laser thickness roughly keeps it inside
    _laserAnimation = Tween<double>(begin: 0.0, end: widget.height - 2.0).animate(_animationController);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          border: Border.all(color: widget.borderColor, width: 3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9), // slightly smaller to account for border thickness
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: _laserAnimation,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _laserAnimation.value),
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          color: widget.laserColor,
                          boxShadow: [
                            BoxShadow(
                              color: widget.laserColor.withValues(alpha: 0.8),
                              blurRadius: 6,
                              spreadRadius: 2,
                              offset: const Offset(0, 0),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
