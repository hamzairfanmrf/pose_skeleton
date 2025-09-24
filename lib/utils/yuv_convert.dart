import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

/// Fast-ish YUV420 → ARGB8888. No crop/pad. No rotation.
/// We’ll stretch to 192×192 later in MoveNet.inferFromImage.
img.Image yuv420ToImage(CameraImage image) {
  final w = image.width, h = image.height;
  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];

  final yRow = yPlane.bytesPerRow;
  final uRow = uPlane.bytesPerRow;
  final vRow = vPlane.bytesPerRow;
  final uPix = uPlane.bytesPerPixel ?? 1;
  final vPix = vPlane.bytesPerPixel ?? 1;

  final yBytes = yPlane.bytes, uBytes = uPlane.bytes, vBytes = vPlane.bytes;

  final out = img.Image(w,h);

  for (int y = 0; y < h; y++) {
    final yBase = y * yRow;
    final uvRow = (y >> 1);
    final uBase = uvRow * uRow;
    final vBase = uvRow * vRow;

    for (int x = 0; x < w; x++) {
      final uvCol = (x >> 1);
      final Y = yBytes[yBase + x];
      final U = uBytes[uBase + uvCol * uPix];
      final V = vBytes[vBase + uvCol * vPix];

      final c = Y - 16;
      final d = U - 128;
      final e = V - 128;

      int r = (298 * c + 409 * e + 128) >> 8;
      int g = (298 * c - 100 * d - 208 * e + 128) >> 8;
      int b = (298 * c + 516 * d + 128) >> 8;
      if (r < 0) r = 0; else if (r > 255) r = 255;
      if (g < 0) g = 0; else if (g > 255) g = 255;
      if (b < 0) b = 0; else if (b > 255) b = 255;

      out.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  return out;
}
