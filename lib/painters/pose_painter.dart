import 'package:flutter/material.dart';
import '../ml/pose_types.dart';

class PosePainter extends CustomPainter {
  final Pose? pose;                // keypoints positions are normalized [0..1]
  final Size displaySize;          // full-screen box we draw into
  final int rotationDeg;           // 0 / 90 / 180 / 270 (from helper)
  final bool mirrorX;              // true for front cam
  final double conf;               // confidence threshold

  PosePainter(
      this.pose, {
        required this.displaySize,
        required this.rotationDeg,
        this.mirrorX = false,
        this.conf = 0.35,
      });

  @override
  @override
  void paint(Canvas canvas, Size size) {
    if (pose == null) return;

    final dstW = displaySize.width;
    final dstH = displaySize.height;

    // BoxFit.cover from unit square to display box
    late Rect fitted;
    if (dstW / dstH < 1.0) {
      final w = dstH;
      fitted = Rect.fromLTWH((dstW - w) / 2, 0, w, dstH);
    } else {
      final h = dstW;
      fitted = Rect.fromLTWH(0, (dstH - h) / 2, dstW, h);
    }

    Offset rot(Offset p, int deg) {
      switch (deg % 360) {
        case 0:   return p;
        case 90:  return Offset(1 - p.dy, p.dx);
        case 180: return Offset(1 - p.dx, 1 - p.dy);
        case 270: return Offset(p.dy, 1 - p.dx);
        default:  return p;
      }
    }

    Offset toScreen(Offset norm) {
      var q = rot(norm, rotationDeg);
      if (mirrorX) q = Offset(1 - q.dx, q.dy);
      return Offset(fitted.left + q.dx * fitted.width,
          fitted.top  + q.dy * fitted.height);
    }

    final pts = <String, Offset>{};
    for (final k in pose!.keypoints) {
      if (k.score < conf) continue;
      pts[k.name] = toScreen(k.position); // position is normalized (x,y)
    }

    final line = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.0;
    final dot  = Paint()..style = PaintingStyle.fill;

    for (final pair in skeletonPairs) {
      final a = pts[pair[0]], b = pts[pair[1]];
      if (a == null || b == null) continue;
      canvas.drawLine(a, b, line);
    }
    for (final p in pts.values) {
      canvas.drawCircle(p, 3.0, dot);
    }
  }


  @override
  bool shouldRepaint(covariant PosePainter old) =>
      old.pose != pose ||
          old.displaySize != displaySize ||
          old.rotationDeg != rotationDeg ||
          old.mirrorX != mirrorX ||
          old.conf != conf;
}
