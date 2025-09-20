// lib/painters/pose_painter_debug.dart
import 'package:flutter/material.dart';

import '../ml/pose_types.dart';

class PosePainterDebug extends CustomPainter {
  final Pose? pose;
  final Size sourceSize;
  final Size displaySize;
  final int rotationDeg;
  final bool mirrorX;
  final double conf;

  PosePainterDebug(
      this.pose, {
        required this.sourceSize,
        required this.displaySize,
        required this.rotationDeg,
        this.mirrorX = false,
        this.conf = 0.35,
      });

  @override
  void paint(Canvas canvas, Size size) {
    if (pose == null || sourceSize.width == 0 || sourceSize.height == 0) return;

    // BoxFit.cover fit
    final srcAR = sourceSize.width / sourceSize.height;
    final dstAR = displaySize.width / displaySize.height;
    late Rect fitted;
    if (srcAR > dstAR) {
      final s = displaySize.height / sourceSize.height;
      final w = sourceSize.width * s;
      fitted = Rect.fromLTWH((displaySize.width - w) / 2, 0, w, displaySize.height);
    } else {
      final s = displaySize.width / sourceSize.width;
      final h = sourceSize.height * s;
      fitted = Rect.fromLTWH(0, (displaySize.height - h) / 2, displaySize.width, h);
    }

    Offset rot(Offset p, Size s, int deg) {
      switch (deg % 360) {
        case 0:   return p;
        case 90:  return Offset(s.height - p.dy, p.dx);
        case 180: return Offset(s.width - p.dx,  s.height - p.dy);
        case 270: return Offset(p.dy,             s.width - p.dx);
        default:  return p;
      }
    }

    // transform to source space
    final src = sourceSize;
    final pts = <int, Offset>{};
    for (int i = 0; i < pose!.keypoints.length; i++) {
      final k = pose!.keypoints[i];
      if (k.score < conf) continue;
      var p = rot(k.position, src, rotationDeg);
      if (mirrorX) p = Offset(src.width - p.dx, p.dy);
      pts[i] = p;
    }

    // draw fitted rect (debug)
    final rectPaint = Paint()
      ..color = const Color(0x80FF0000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(fitted, rectPaint);

    // scale to fitted
    canvas.save();
    canvas.translate(fitted.left, fitted.top);
    final sx = fitted.width / sourceSize.width;
    final sy = fitted.height / sourceSize.height;
    canvas.scale(sx, sy);

    final s = (sx + sy) * 0.5;
    final line = Paint()..style = PaintingStyle.stroke..strokeWidth = 2 / s;
    final dot  = Paint()..style = PaintingStyle.fill..strokeWidth = 1 / s;

    // lines
    final mapByName = {for (int i = 0; i < pose!.keypoints.length; i++) pose!.keypoints[i].name: i};
    for (final pair in skeletonPairs) {
      final ia = mapByName[pair[0]], ib = mapByName[pair[1]];
      if (ia == null || ib == null) continue;
      final a = pts[ia], b = pts[ib];
      if (a == null || b == null) continue;
      canvas.drawLine(a, b, line);
    }
    // points + index labels
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final e in pts.entries) {
      final p = e.value;
      canvas.drawCircle(p, 3 / s, dot);
      tp.text = TextSpan(
          text: e.key.toString(),
          style: TextStyle(color: Colors.yellow, fontSize: 10 / s, fontWeight: FontWeight.bold));
      tp.layout();
      tp.paint(canvas, p + const Offset(2, -2));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PosePainterDebug old) => true;
}
