// lib/pages/camera_page.dart
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle, DeviceOrientation;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../ml/pose_types.dart';
import '../services/camera_service.dart';
import '../services/pose_isolate.dart';
import '../painters/pose_painter.dart';
import '../utils/fps_counter.dart';
import '../services/pose_isolate.dart' as pose;

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final fps = FpsCounter();
  Pose? currentPose;

  bool performanceMode = true;
  int downsample = 2;
  final cam = CameraService(preset: ResolutionPreset.medium);

  StreamSubscription? _sub;
  FrameData? lastFrame;

  late final pose.PoseIsolate iso; // <-- prefixed
  SendPort? isoPort;

  // rotation tweak button
  int _rotAdjust = 0; // tap button to cycle 0/90/180/270

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  // ...

  Future<void> _bootstrap() async {
    await cam.init();

    // load your correct model
    final bd = await rootBundle.load('assets/models/movenet2.tflite');
    final modelBytes = bd.buffer.asUint8List();

    // start isolate (prefixed)
    iso = pose.PoseIsolate();
    isoPort = await iso.start(modelBytes, inputSize: 192);

    await cam.start(downsample: true ? 2 : 1, outSize: 192);
    _sub = cam.frames.listen(_onFrame);

    setState(() {});
  }

// 1) In _onFrame: store the frame, then set pose
  Future<void> _onFrame(FrameData frame) async {
    if (isoPort == null) return;

    lastFrame = frame; // <-- ADD THIS

    final recv = ReceivePort();
    isoPort!.send([recv.sendPort, pose.PoseRequest(frame.rgb, const Size(1, 1))]);
    final resp = await recv.first as pose.PoseResponse;

    setState(() {
      currentPose = resp.pose;
      fps.tick();
    });
  }


  @override
  void dispose() {
    _sub?.cancel();
    cam.stop();
    cam.dispose();
    iso.dispose(); // <-- prefixed
    super.dispose();
  }

  // Compute rotation from image (sensor) to display (CameraPreview)
  int rotationImageToDisplay(CameraController c) {
    final sensor = c.description.sensorOrientation;
    final map = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final device = map[c.value.deviceOrientation] ?? 0;
    final isFront = c.description.lensDirection == CameraLensDirection.front;
    return isFront ? (sensor + device) % 360 : (sensor - device + 360) % 360;
  }

  @override
  @override
  Widget build(BuildContext context) {
    if (!cam.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final ctrl = cam.controller!;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final box = constraints.biggest;
          final side = box.shortestSide;
          final cropDisp = Rect.fromLTWH(
            (box.width - side) / 2,
            (box.height - side) / 2,
            side,
            side,
          );

          final pv = ctrl.value.previewSize!;
          final previewW = pv.height; // swapped
          final previewH = pv.width;


          return Stack(
            fit: StackFit.expand,
            children: [
              // Camera preview
              SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: previewW,
                    height: previewH,
                    child: CameraPreview(ctrl),
                  ),
                ),
              ),

              // Skeleton overlay
              if (currentPose != null)
                CustomPaint(
                  size: box,
                  painter: PosePainter(
                    currentPose,
                    displaySize: box,
                    cropInDisplay: cropDisp,
                    conf: 0.03, // raise threshold now
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
