// lib/painters/pose_painter.dart
import 'package:flutter/material.dart';
import '../ml/pose_types.dart';

class PosePainter extends CustomPainter {
  final Pose? pose;
  final Size displaySize;
  final Rect cropInDisplay; // the square you feed to the model
  final double conf;        // recommended 0.3 for real use

  PosePainter(
      this.pose, {
        required this.displaySize,
        required this.cropInDisplay,
        this.conf = 0.3,
      });

  // COCO skeleton pairs (0..16)
  static const edges = <List<int>>[
    [0,1],[0,2],[1,3],[2,4],         // eyes/ears
    [0,5],[0,6],[5,7],[7,9],         // left arm
    [6,8],[8,10],                    // right arm
    [5,6],[5,11],[6,12],[11,12],     // shoulders/hips (torso)
    [11,13],[13,15],                 // left leg
    [12,14],[14,16],                 // right leg
  ];

  // Helper to map normalized (0..1) coords to crop rectangle on screen
  Offset _map(Offset n) => Offset(
    cropInDisplay.left + n.dx * cropInDisplay.width,
    cropInDisplay.top  + n.dy * cropInDisplay.height,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final p = pose;
    if (p == null) return;

    // Build list of points and visibility by confidence
    final pts = List<Offset?>.filled(17, null);
    final vis = List<bool>.filled(17, false);
    for (var i = 0; i < p.keypoints.length && i < 17; i++) {
      final k = p.keypoints[i];
      if (k.score >= conf) {
        final xy = _map(k.position); // position is normalized (x,y)
        pts[i] = xy;
        vis[i] = true;
      }
    }

    // Optional torso gating: if shoulders/hips are not visible, skip arms/legs
    final torsoVisible = vis[5] && vis[6] && vis[11] && vis[12];

    final jointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final bonePaint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    // Draw joints that passed the threshold
    for (final pt in pts) {
      if (pt != null) canvas.drawCircle(pt, 4, jointPaint);
    }

    // Draw only edges whose both joints are visible
    for (final e in edges) {
      final a = e[0], b = e[1];
      // If torso not visible, only allow face/shoulder edges
      if (!torsoVisible) {
        final allowedWhenNoTorso = const {
          // eyes/ears + head-to-shoulder lines
          [0,1], [0,2], [1,3], [2,4], [0,5], [0,6]
        };
        // quick set-like contains check
        bool ok = false;
        for (final pair in allowedWhenNoTorso) {
          if ((pair[0] == a && pair[1] == b) || (pair[0] == b && pair[1] == a)) {
            ok = true; break;
          }
        }
        if (!ok) continue;
      }

      final pa = pts[a], pb = pts[b];
      if (pa != null && pb != null) {
        canvas.drawLine(pa, pb, bonePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter old) =>
      old.pose != pose ||
          old.displaySize != displaySize ||
          old.cropInDisplay != cropInDisplay ||
          old.conf != conf;
}
