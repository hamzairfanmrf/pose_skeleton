// lib/services/camera_service.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class FrameData {
  final Uint8List rgb;        // RGB bytes at model input (size x size x 3)
  final int size;             // model input size (e.g., 192 or 256)

  // Source (sensor-rotated) full image size (CameraImage.width/height):
  final int srcW, srcH;

  // Square crop (in source coords) that was center-cropped before resize:
  final int cropX, cropY, cropSize;

  const FrameData(
      this.rgb,
      this.size,
      this.srcW,
      this.srcH,
      this.cropX,
      this.cropY,
      this.cropSize,
      );
}

class CameraService {
  final ResolutionPreset preset;
  CameraController? _controller; // nullable until initialized
  CameraDescription? camera;

  final _out = StreamController<FrameData>.broadcast();
  bool _streaming = false;

  CameraService({this.preset = ResolutionPreset.medium});

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  Stream<FrameData> get frames => _out.stream;

  Future<void> init() async {
    final cameras = await availableCameras();
    camera = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      camera!,
      ResolutionPreset.low, // <= try low for speed on Redmi Note 10 5G
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _controller!.initialize();

    // Debug once
    // ignore: avoid_print
    print('sensor=${_controller!.description.sensorOrientation} '
        'device=${_controller!.value.deviceOrientation} '
        'lens=${_controller!.description.lensDirection}');
  }

  Future<void> start({int downsample = 2, int outSize = 192}) async {
    if (_streaming || _controller == null) return;
    _streaming = true;

    int i = 0;
    await _controller!.startImageStream((CameraImage img) async {
      if (!_streaming) return;
      if ((++i % downsample) != 0) return;

      // run conversion on this isolate (no compute())
      final res = _convertWorker(_ConvertParams(img, outSize));

      _out.add(FrameData(res.rgb, outSize, res.srcW, res.srcH, /* crop fields not used */ 0,0,0));

    });
  }


  Future<void> stop() async {
    if (!_streaming || _controller == null) return;
    _streaming = false;
    try {
      await _controller!.stopImageStream();
    } catch (_) {
      // ignore stop errors if stream already stopped
    }
  }

  void dispose() {
    _out.close();
    _controller?.dispose();
  }
}

// ---------- background converter (runs in compute) ----------

// in camera_service.dart (or wherever your converter lives)
class _ConvertParams {
  final CameraImage img;
  final int outSize;
  const _ConvertParams(this.img, this.outSize);
}

class _ConvertResult {
  final Uint8List rgb; // NHWC packed RGB (outSize*outSize*3)
  final int srcW, srcH;
  const _ConvertResult(this.rgb, this.srcW, this.srcH);
}

// Stretch resize: whole sensor frame -> out×out, no crop/pad (like Android ResizeOp(192,192))
_ConvertResult _convertWorker(_ConvertParams p) {
  final img = p.img;
  final out = p.outSize;

  final srcW = img.width, srcH = img.height;

  final yPlane = img.planes[0];
  final uPlane = img.planes[1];
  final vPlane = img.planes[2];

  final yBytes = yPlane.bytes;
  final uBytes = uPlane.bytes;
  final vBytes = vPlane.bytes;

  final yRow = yPlane.bytesPerRow;
  final uRow = uPlane.bytesPerRow;
  final vRow = vPlane.bytesPerRow;

  final uPix = uPlane.bytesPerPixel ?? 1;
  final vPix = vPlane.bytesPerPixel ?? 1;

  final outW = out, outH = out;
  final rgb = Uint8List(outW * outH * 3);

  // independent scales (NO aspect lock)
  final scaleX = srcW / outW;
  final scaleY = srcH / outH;

  int o = 0;
  for (int oy = 0; oy < outH; oy++) {
    final sy = (oy * scaleY).floor().clamp(0, srcH - 1);
    final uvSy = sy >> 1;
    final yBase = sy * yRow, uBase = uvSy * uRow, vBase = uvSy * vRow;

    for (int ox = 0; ox < outW; ox++) {
      final sx = (ox * scaleX).floor().clamp(0, srcW - 1);
      final uvSx = sx >> 1;

      final Y = yBytes[yBase + sx];
      final U = uBytes[uBase + uvSx * uPix];
      final V = vBytes[vBase + uvSx * vPix];

      // BT.601 fast YUV->RGB
      final c = Y - 16;
      final d = U - 128;
      final e = V - 128;
      int r = (298 * c + 409 * e + 128) >> 8;
      int g = (298 * c - 100 * d - 208 * e + 128) >> 8;
      int b = (298 * c + 516 * d + 128) >> 8;
      if (r < 0) r = 0; else if (r > 255) r = 255;
      if (g < 0) g = 0; else if (g > 255) g = 255;
      if (b < 0) b = 0; else if (b > 255) b = 255;

      rgb[o++] = r; rgb[o++] = g; rgb[o++] = b;
    }
  }

  return _ConvertResult(rgb, srcW, srcH);
}

