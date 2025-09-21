// lib/pages/mlkit_pose_page.dart
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class MlkitPosePage extends StatefulWidget {
  const MlkitPosePage({super.key});
  @override
  State<MlkitPosePage> createState() => _MlkitPosePageState();
}

class _MlkitPosePageState extends State<MlkitPosePage> {
  CameraController? _cam;
  late final PoseDetector _pose;
  Pose? _lastPose;
  Size _lastImageSize = Size.zero;
  bool _busy = false; // prevent overlapping inferences
  double _fps = 0;
  DateTime _lastTick = DateTime.now();

  @override
  void initState() {
    super.initState();
    _pose = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.base, // or .accurate (slower, steadier)
      ),
    );
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cams = await availableCameras();
    final back = cams.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cams.first,
    );
    _cam = CameraController(
      back,
      ResolutionPreset.medium, // keep this modest for FPS
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _cam!.initialize();
    if (!mounted) return;
    await _cam!.startImageStream(_onImage);
    setState(() {});
  }

  Future<void> _onImage(CameraImage img) async {
    if (_busy) return;
    _busy = true;

    try {
      // Build ML Kit InputImage from YUV420 camera buffers
      final WriteBuffer wb = WriteBuffer();
      for (final p in img.planes) {
        wb.putUint8List(p.bytes);
      }
      final bytes = wb.done().buffer.asUint8List();

      final rotation = InputImageRotationValue.fromRawValue(
        _cam!.description.sensorOrientation,
      ) ??
          InputImageRotation.rotation0deg;

      final format = InputImageFormatValue.fromRawValue(img.format.raw) ??
          InputImageFormat.nv21;

      final input = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(img.width.toDouble(), img.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: img.planes.first.bytesPerRow,
        ),
      );

      final poses = await _pose.processImage(input);
      if (!mounted) return;

      // FPS
      final now = DateTime.now();
      final dtMs = now.difference(_lastTick).inMilliseconds;
      if (dtMs > 0) _fps = 1000 / dtMs;
      _lastTick = now;

      setState(() {
        _lastPose = poses.isNotEmpty ? poses.first : null;
        _lastImageSize = Size(img.width.toDouble(), img.height.toDouble());
      });
    } catch (_) {
      // swallow for now
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _cam?.dispose();
    _pose.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cam == null || !_cam!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // CameraPreview size comes in sensor coords; swap for portrait
    final pv = _cam!.value.previewSize!;
    final previewW = pv.height;
    final previewH = pv.width;

    // Full-screen overlay size
    final box = MediaQuery.of(context).size;

    // Compute the fitted rect (how the camera image is scaled into screen)
    final imgAR = previewW / previewH;
    final dispAR = box.width / box.height;
    Rect fitted;
    if (imgAR > dispAR) {
      // image is wider -> match height, crop left/right
      final h = box.height;
      final w = h * imgAR;
      fitted = Rect.fromLTWH((box.width - w) / 2, 0, w, h);
    } else {
      // image is taller -> match width, crop top/bottom
      final w = box.width;
      final h = w / imgAR;
      fitted = Rect.fromLTWH(0, (box.height - h) / 2, w, h);
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Cover the whole screen with the preview
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: previewW,
              height: previewH,
              child: CameraPreview(_cam!),
            ),
          ),

          // Skeleton overlay
          CustomPaint(
            size: box,
            painter: _MlkitPosePainter(
              _lastPose,
              displaySize: box,
              imageSize: _lastImageSize,
              fittedRect: fitted,
              conf: 0.35, // adjust 0.3–0.5 for clean lines
            ),
          ),

          // Chips
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _chip('ML Kit Pose'),
                  const SizedBox(width: 8),
                  _chip('${_fps.toStringAsFixed(1)} FPS'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.55),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w600)),
  );
}

/// Draws 33-landmark skeleton; maps ML Kit's image pixel coords into the
/// exact rectangle where the preview image is drawn (fittedRect).
class _MlkitPosePainter extends CustomPainter {
  final Pose? pose;
  final Size displaySize;  // screen size
  final Size imageSize;    // camera image size (in pixels)
  final Rect fittedRect;   // where the preview is drawn on screen
  final double conf;

  _MlkitPosePainter(
      this.pose, {
        required this.displaySize,
        required this.imageSize,
        required this.fittedRect,
        this.conf = 0.3,
      });

  // A clean subset of bones for readability (you can add more)
  static const edges = <List<PoseLandmarkType>>[
    // head/eyes
    [PoseLandmarkType.leftEye, PoseLandmarkType.rightEye],
    [PoseLandmarkType.leftEar, PoseLandmarkType.leftEye],
    [PoseLandmarkType.rightEar, PoseLandmarkType.rightEye],
    // shoulders & arms
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    // torso
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    // legs
    [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
    [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (pose == null || imageSize == Size.zero) return;

    // Map image-pixel coords -> fittedRect on screen
    Offset map(double x, double y) => Offset(
      fittedRect.left + (x / imageSize.width) * fittedRect.width,
      fittedRect.top + (y / imageSize.height) * fittedRect.height,
    );

    final jointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final bonePaint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Collect points with confidence
    final pts = <PoseLandmarkType, Offset>{};
    for (final entry in pose!.landmarks.entries) {
      final lm = entry.value;
      if (lm.likelihood != null && lm.likelihood! < conf) continue;
      pts[entry.key] = map(lm.x, lm.y);
    }

    // Draw joints
    for (final o in pts.values) {
      canvas.drawCircle(o, 4, jointPaint);
    }

    // Draw bones (only when both ends exist)
    for (final e in edges) {
      final a = pts[e[0]];
      final b = pts[e[1]];
      if (a != null && b != null) canvas.drawLine(a, b, bonePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MlkitPosePainter old) =>
      old.pose != pose ||
          old.displaySize != displaySize ||
          old.imageSize != imageSize ||
          old.fittedRect != fittedRect ||
          old.conf != conf;
}
