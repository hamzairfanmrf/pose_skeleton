import 'package:flutter/material.dart';
import '../ml/pose_types.dart';
class PosePainter extends CustomPainter {
  final Pose? pose;
  PosePainter(this.pose);

  @override
  void paint(Canvas canvas, Size size) {
    if (pose == null) return;
    final kp = {for (final k in pose!.keypoints) k.name: k};
    final dot = Paint()..style = PaintingStyle.fill..strokeWidth = 3;
    final line = Paint()..style = PaintingStyle.stroke..strokeWidth = 3;
    for (final p in skeletonPairs) {
      final a = kp[p[0]]; final b = kp[p[1]];
      if (a == null || b == null) continue;
      if (a.score < 0.2 || b.score < 0.2) continue;
      canvas.drawLine(a.position, b.position, line);
    }
    for (final k in kp.values) {
      if (k.score < 0.2) continue;
      canvas.drawCircle(k.position, 4, dot);
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter old) => old.pose != pose;
}