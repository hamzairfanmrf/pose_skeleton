import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:camera/camera.dart';

import '../ml/pose_types.dart';
import '../ml/movenet.dart';
import '../painters/pose_painter.dart';
// Make sure the file name matches your actual file: yuv_converter.dart
import '../utils/yuv_convert.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? _controller;
  MoveNet? _net;
  Pose? _pose;
  int _skip = 0; // simple frame skipping for perf

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Future<void> _initAll() async {
    // 1) Camera
    final cameras = await availableCameras();
    final back = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      back,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();

    // 2) Model
    final model = await rootBundle.load(
      'assets/models/lite-model_movenet_singlepose_lightning_tflite_float16_4.tflite',
    );
    _net = await MoveNet.load(model.buffer.asUint8List(), inputSize: 192, threads: 4);

    // 3) Stream + inference (THIS is where your snippet lives)
    await _controller!.startImageStream((CameraImage camImg) async {
      // Light frame skipping (process every 2nd frame)
      _skip = (_skip + 1) % 2;
      if (_skip != 0) return;

      final net = _net;
      if (net == null) return;

      // 1) YUV → ARGB image
      final rgbImage = yuv420ToImage(camImg);

      // 2) Run MoveNet (handles resize/normalize internally to 192×192)
      final pose = net.inferFromImage(rgbImage);

      // 3) Update UI
      if (!mounted) return;
      setState(() => _pose = pose);
    });

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    _net?.close();
    super.dispose();
  }

  // Compute the on-screen rectangle of the camera preview (BoxFit.cover)
  Rect _previewRectOnScreen(Size screen, Size src) {
    final fitted = applyBoxFit(BoxFit.cover, src, screen);
    return Alignment.center.inscribe(fitted.destination, Offset.zero & screen);
  }

  // Sensor preview size converted to portrait
  Size _srcSizePortrait(CameraController c) {
    final pv = c.value.previewSize!;
    return Size(pv.height, pv.width); // swap to portrait
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final box = constraints.biggest;

          // Use your actual controller
          final controller = _controller!;
          final pv = controller.value.previewSize!;
          final srcSize = Size(pv.height, pv.width); // portrait orientation

          // Where the CameraPreview is drawn on screen (BoxFit.cover)
          final fitted = applyBoxFit(BoxFit.cover, srcSize, box);
          final previewRect =
          Alignment.center.inscribe(fitted.destination, Offset.zero & box);

          return Stack(
            fit: StackFit.expand,
            children: [
              // Camera preview
              SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: srcSize.width,
                    height: srcSize.height,
                    child: CameraPreview(controller),
                  ),
                ),
              ),

              // DOTS overlay (use _pose, not currentPose)
              if (_pose != null)
                CustomPaint(
                  size: box,
                  painter: PosePainter(
                    _pose,
                    previewOnScreen: previewRect,
                    srcSize: srcSize,
                    conf: 0.5,
                    radius: 4,
                    color: Colors.yellow,
                    mirrorX: false,   // back camera only
                    rotationDeg: 0,   // set 90/180/270 if needed
                  ),
                ),
            ],
          );
        },
      ),
    );

  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.55),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
    ),
  );
}
