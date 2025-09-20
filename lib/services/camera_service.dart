import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class FrameData {
  final Uint8List rgb; // packed RGB at model input size
  final int size; // inputSize (e.g., 192)
  final int srcW, srcH; // source preview size
  const FrameData(this.rgb, this.size, this.srcW, this.srcH);
}

class CameraService {
  final ResolutionPreset preset;
  CameraController? _controller; // <-- nullable
  CameraDescription? camera;
  final _out = StreamController<FrameData>.broadcast();
  bool _streaming = false;

  CameraService({this.preset = ResolutionPreset.medium});

  CameraController? get controller => _controller; // <-- nullable getter
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  Stream<FrameData> get frames => _out.stream;

  Future<void> init() async {
    final cameras = await availableCameras();
    camera = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    _controller = CameraController(
      camera!, preset,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();
    print('sensor=${controller!.description.sensorOrientation} '
        'device=${controller!.value.deviceOrientation} '
        'lens=${controller!.description.lensDirection}');
  }

  Future<void> start({int downsample = 2, int outSize = 192}) async {
    if (_streaming || _controller == null) return;
    _streaming = true;
    int i = 0;
    await _controller!.startImageStream((CameraImage img) async {
      if (!_streaming) return;
      i++; if (i % downsample != 0) return;

      final rgb = await compute<_ConvertParams, Uint8List>(
        _convertWorker,
        _ConvertParams(img, outSize), // outSize == 192
      );

      // ✅ Tell consumers the source space is the model input (192×192), not the camera frame
      _out.add(FrameData(rgb, outSize, outSize, outSize));
    });


  }

  Future<void> stop() async {
    if (!_streaming || _controller == null) return;
    _streaming = false;
    await _controller!.stopImageStream();
  }

  void dispose() {
    _out.close();
    _controller?.dispose();
  }
}

class _ConvertParams {
  final CameraImage img; final int outSize;
  const _ConvertParams(this.img, this.outSize);
}

/// Convert YUV420 (I420 or NV21/NV12) directly to RGB at outSize×outSize.
Uint8List _convertWorker(_ConvertParams p) {
  final img = p.img;
  final out = p.outSize;

  final srcW = img.width, srcH = img.height;
  final y = img.planes[0];
  final u = img.planes[1];
  final v = img.planes[2];

  final yBytes = y.bytes;
  final uBytes = u.bytes;
  final vBytes = v.bytes;

  final yRowStride = y.bytesPerRow;
  final uRowStride = u.bytesPerRow;
  final vRowStride = v.bytesPerRow;

  final uPixStride = u.bytesPerPixel ?? 1; // 1: I420, 2: NV12/NV21
  final vPixStride = v.bytesPerPixel ?? 1;

  // --- center-crop to square (cover) ---
  final crop = srcW < srcH ? srcW : srcH;
  final cropX = (srcW - crop) >> 1;
  final cropY = (srcH - crop) >> 1;

  final outW = out, outH = out;
  final rgb = Uint8List(outW * outH * 3);

  // scale from cropped square -> out
  final xRatio = crop / outW;
  final yRatio = crop / outH;

  int o = 0;
  for (int oy = 0; oy < outH; oy++) {
    final syInCrop = (oy * yRatio).floor();      // 0..crop-1
    final sy = cropY + syInCrop;                  // 0..srcH-1

    final uvSy = sy >> 1;
    final yBase = sy * yRowStride;
    final uBase = uvSy * uRowStride;
    final vBase = uvSy * vRowStride;

    for (int ox = 0; ox < outW; ox++) {
      final sxInCrop = (ox * xRatio).floor();    // 0..crop-1
      final sx = cropX + sxInCrop;                // 0..srcW-1
      final uvSx = sx >> 1;

      final yIndex = yBase + sx;
      final uIndex = uBase + uvSx * uPixStride;
      final vIndex = vBase + uvSx * vPixStride;

      int Y = yBytes[yIndex];
      int U = uBytes[uIndex];
      int V = vBytes[vIndex];

      // BT.601 YUV -> RGB
      final c = Y - 16;
      final d = U - 128;
      final e = V - 128;

      int r = (298 * c + 409 * e + 128) >> 8;
      int g = (298 * c - 100 * d - 208 * e + 128) >> 8;
      int b = (298 * c + 516 * d + 128) >> 8;

      if (r < 0) r = 0; else if (r > 255) r = 255;
      if (g < 0) g = 0; else if (g > 255) g = 255;
      if (b < 0) b = 0; else if (b > 255) b = 255;

      rgb[o++] = r;
      rgb[o++] = g;
      rgb[o++] = b;
    }
  }
  return rgb;
}
