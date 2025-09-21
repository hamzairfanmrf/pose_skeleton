import 'dart:ui';

/// Models tf.image.resize_with_pad as an affine transform:
/// dst = A * src + t, where scale = min(tH/srcH, tW/srcW),
/// and padding offsets are (dx, dy).
class ResizeWithPad {
  final double srcW, srcH;
  final double dstW, dstH;
  final double scale; // isotropic
  final double dx, dy; // padding offsets in dst space

  ResizeWithPad({
    required this.srcW,
    required this.srcH,
    required this.dstW,
    required this.dstH,
  })  : scale = (dstH / srcH < dstW / srcW) ? (dstH / srcH) : (dstW / srcW),
        dx = (dstW - ((dstH / srcH < dstW / srcW) ? (dstH / srcH) : (dstW / srcW)) * srcW) * 0.5,
        dy = (dstH - ((dstH / srcH < dstW / srcW) ? (dstH / srcH) : (dstW / srcW)) * srcH) * 0.5;

  /// Map a source pixel (x,y) to dst (after resize_with_pad).
  Offset srcToDst(Offset p) => Offset(
    dx + p.dx * scale,
    dy + p.dy * scale,
  );

  /// Map a dst pixel (x,y) (after resize_with_pad) back to source.
  Offset dstToSrc(Offset p) => Offset(
    (p.dx - dx) / scale,
    (p.dy - dy) / scale,
  );
}
