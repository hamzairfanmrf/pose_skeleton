// lib/utils/pose_stabilizer.dart
import 'dart:ui';
import '../ml/pose_types.dart';

class _KpState {
  Offset pos = const Offset(0,0);
  double score = 0;
  bool has = false;
}

class PoseStabilizer {
  final double alpha;         // EMA strength (0.0..1.0) ~ 0.4 works well
  final double appear;        // show when score >= appear
  final double disappear;     // keep drawing until score < disappear
  final List<_KpState> _s = List.generate(17, (_) => _KpState());

  PoseStabilizer({this.alpha = 0.4, this.appear = 0.15, this.disappear = 0.05});

  Pose update(Pose raw) {
    final out = <Keypoint>[];

    for (int i = 0; i < 17; i++) {
      final r = raw.keypoints[i];
      final st = _s[i];

      final seen = r.score >= appear || (st.has && r.score >= disappear);

      if (!st.has) {
        // initialize on first sighting
        st.pos = r.position;
        st.score = r.score;
        st.has = seen;
      }

      if (seen) {
        // EMA smoothing on (x,y) in normalized space
        final ax = alpha;
        st.pos = Offset(
          ax * r.position.dx + (1-ax) * st.pos.dx,
          ax * r.position.dy + (1-ax) * st.pos.dy,
        );
        st.score = 0.5 * r.score + 0.5 * st.score; // mild score smoothing
        st.has = true;

        out.add(Keypoint(r.name, st.pos, st.score));
      } else {
        // keep last if you prefer “hold”, or output a very low score:
        out.add(Keypoint(r.name, st.pos, 0.0));
        st.has = false;
      }
    }

    return Pose(out);
  }

  void reset() {
    for (final s in _s) { s.has = false; s.score = 0; s.pos = const Offset(0,0); }
  }
}
