import 'package:flutter/material.dart';
import '../ml/pose_types.dart';

/// Draws only keypoint dots at the model's normalized positions.
/// It maps (x,y in 0..1) into the same fitted rectangle where the
/// camera preview is rendered.
class PosePainter extends CustomPainter {
  final Pose? pose;
  final Rect fullInDisplay;   // where the camera frame sits on screen
  final double conf;          // confidence threshold
  final int rotationDeg;      // 0/90/180/270 image->display rotation
  final bool mirrorX;         // true for front camera
  final double radius;        // dot radius
  final Color color;          // dot color

  PosePainter(
      this.pose, {
        required this.fullInDisplay,
        this.conf = 0.25,
        this.rotationDeg = 0,
        this.mirrorX = false,
        this.radius = 4.0,
        this.color = Colors.cyanAccent,
      });

  Offset _normToRect(Offset n) => Offset(
    fullInDisplay.left + n.dx * fullInDisplay.width,
    fullInDisplay.top  + n.dy * fullInDisplay.height,
  );

  Offset _applyMirror(Offset p) {
    if (!mirrorX) return p;
    final cx = fullInDisplay.center.dx;
    return Offset(2 * cx - p.dx, p.dy);
  }

  Offset _applyRotation(Offset p) {
    final r = rotationDeg % 360;
    if (r == 0) return p;
    final c = fullInDisplay.center;
    final dx = p.dx - c.dx, dy = p.dy - c.dy;
    switch (r) {
      case 90:  return Offset(c.dx - dy, c.dy + dx);
      case 180: return Offset(c.dx - dx, c.dy - dy);
      case 270: return Offset(c.dx + dy, c.dy - dx);
      default:  return p;
    }
  }

  Offset _toDisplay(Offset norm) =>
      _applyRotation(_applyMirror(_normToRect(norm)));

  @override
  void paint(Canvas canvas, Size size) {
    final p = pose;
    if (p == null) return;

    final dot = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (var i = 0; i < p.keypoints.length && i < 17; i++) {
      final k = p.keypoints[i];
      if (k.score < conf) continue;
      final pt = _toDisplay(k.position); // position is normalized (x,y)
      canvas.drawCircle(pt, radius, dot);
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter old) =>
      old.pose != pose ||
          old.fullInDisplay != fullInDisplay ||
          old.conf != conf ||
          old.rotationDeg != rotationDeg ||
          old.mirrorX != mirrorX ||
          old.radius != radius ||
          old.color != color;
}
