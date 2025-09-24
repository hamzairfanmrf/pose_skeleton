// lib/painters/pose_painter.dart
import 'package:flutter/material.dart';
import '../ml/pose_types.dart';

/// Draws pose keypoints as dots, mapping normalized (0..1) coords
/// from the *full source frame* to the exact on-screen preview rect
/// painted with BoxFit.cover.
///
/// NO crop math here. If you used a center-crop before, remove it
/// (or set srcSize to that crop and pass the preview rect that shows it).
class PosePainter extends CustomPainter {
  final Pose? pose;

  /// The exact rectangle where CameraPreview is drawn on screen.
  final Rect previewOnScreen;

  /// Source sensor size expressed in the same orientation you used for preview,
  /// e.g. Size(pv.height, pv.width) for portrait UI.
  final Size srcSize;

  /// Confidence threshold for drawing.
  final double conf;

  /// Dot appearance.
  final double radius;
  final Color color;

  /// Visual tweaks.
  final bool mirrorX;     // true for front camera
  final int rotationDeg;  // 0 / 90 / 180 / 270

  const PosePainter(
      this.pose, {
        required this.previewOnScreen,
        required this.srcSize,
        this.conf = 0.45,
        this.radius = 4,
        this.color = Colors.yellow,
        this.mirrorX = false,
        this.rotationDeg = 0,
      });

  @override
  void paint(Canvas canvas, Size size) {
    final p = pose;
    if (p == null) return;

    // Scale factors from source pixels -> screen pixels
    final sx = previewOnScreen.width  / srcSize.width;
    final sy = previewOnScreen.height / srcSize.height;

    final dot = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (final k in p.keypoints) {
      if (k.score < conf) continue;

      // 1) normalized -> source px
      double x = k.position.dx * srcSize.width;
      double y = k.position.dy * srcSize.height;

      // 2) optional rotation in source space (around the source center)
      if (rotationDeg % 360 != 0) {
        final cx = srcSize.width  * 0.5;
        final cy = srcSize.height * 0.5;

        final dx = x - cx;
        final dy = y - cy;

        switch (rotationDeg % 360) {
          case 90:   // clockwise
            x = cx + dy;
            y = cy - dx;
            break;
          case 180:
            x = cx - dx;
            y = cy - dy;
            break;
          case 270:
            x = cx - dy;
            y = cy + dx;
            break;
        }
      }

      // 3) optional mirror (flip horizontally)
      if (mirrorX) {
        x = srcSize.width - x;
      }

      // 4) source -> screen
      final scrX = previewOnScreen.left + x * sx;
      final scrY = previewOnScreen.top  + y * sy;

      canvas.drawCircle(Offset(scrX, scrY), radius, dot);
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter old) {
    return old.pose != pose ||
        old.previewOnScreen != previewOnScreen ||
        old.srcSize != srcSize ||
        old.conf != conf ||
        old.radius != radius ||
        old.color != color ||
        old.mirrorX != mirrorX ||
        old.rotationDeg != rotationDeg;
  }
}
