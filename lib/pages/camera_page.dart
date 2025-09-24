// lib/pages/camera_page.dart  (only the interesting parts shown)
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle, DeviceOrientation;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../ml/pose_types.dart';
import '../services/camera_service.dart';
import '../services/pose_isolate.dart' as pose;
import '../painters/pose_painter.dart';
import '../utils/fps_counter.dart';
import '../utils/pose_stabilizer.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final fps = FpsCounter();
  final cam = CameraService(preset: ResolutionPreset.medium);
  final stabilizer = PoseStabilizer(alpha: 0.4, appear: 0.15, disappear: 0.07);

  Pose? currentPose;
  pose.PoseIsolate? iso;
  SendPort? isoPort;
  StreamSubscription? _sub;

  int _rotAdjust = 0;

  @override
  void initState() { super.initState(); _bootstrap(); }

  Future<void> _bootstrap() async {
    await cam.init();

    final bd = await rootBundle.load(
      'assets/models/lite-model_movenet_singlepose_lightning_tflite_float16_4.tflite',
    );
    final modelBytes = bd.buffer.asUint8List();

    iso = pose.PoseIsolate();
    isoPort = await iso!.start(modelBytes, inputSize: 192);

    await cam.start(downsample: 2, outSize: 192);
    _sub = cam.frames.listen(_onFrame);

    setState(() {});
  }

  Future<void> _onFrame(FrameData f) async {
    if (isoPort == null) return;
    final recv = ReceivePort();
    isoPort!.send([recv.sendPort, pose.PoseRequest(f.rgb, const Size(1, 1))]);
    final resp = await recv.first as pose.PoseResponse;
    setState(() { currentPose = stabilizer.update(resp.pose); fps.tick(); });
  }

  @override
  void dispose() { _sub?.cancel(); cam.stop(); cam.dispose(); iso?.dispose(); super.dispose(); }

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

  // Compute where the preview lands on screen with BoxFit.cover
  Rect _fittedRect(Size src, Size dst) {
    final scale = (dst.width / src.width > dst.height / src.height)
        ? dst.width / src.width
        : dst.height / src.height;
    final w = src.width * scale, h = src.height * scale;
    final left = (dst.width - w) / 2, top = (dst.height - h) / 2;
    return Rect.fromLTWH(left, top, w, h);
  }

  @override
  Widget build(BuildContext context) {
    if (!cam.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final ctrl = cam.controller!;
    final rot = (rotationImageToDisplay(ctrl) + _rotAdjust) % 360;
    final isFront = ctrl.description.lensDirection == CameraLensDirection.front;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          // inside LayoutBuilder -> builder:
          final box = constraints.biggest;

// The camera stream size as we feed into FittedBox:
          final pv = ctrl.value.previewSize!;
          final srcSize = Size(pv.height, pv.width); // swap to portrait

// Ask Flutter how BoxFit.cover will scale src into the screen box
          final fittedSizes = applyBoxFit(BoxFit.cover, srcSize, box);
          final dest = Alignment.center.inscribe(fittedSizes.destination, Offset.zero & box);

// 'dest' is the *exact* rectangle where the preview is drawn on screen
          final previewRectOnScreen = dest;
          final fitted = _fittedRect(srcSize, box);

          return Stack(
            fit: StackFit.expand,
            children: [
              // Preview matches fitted rect via BoxFit.cover
              SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: srcSize.width,
                    height: srcSize.height,
                    child: CameraPreview(ctrl),
                  ),
                ),
              ),

              if (currentPose != null)
                CustomPaint(
                  size: box,
                  painter: PosePainter(
                    currentPose,
                    fullInDisplay: fitted,   // <— draw in the same rect as preview
                    rotationDeg: rot,
                    mirrorX: isFront,
                    conf: 0.25,
                  ),
                ),

              // Chips + rotation tweak
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const _Chip(text: 'MoveNet Lightning (fp16)'),
                      const SizedBox(width: 8),
                      _Chip(text: '${fps.fps.toStringAsFixed(1)} FPS'),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Rotate overlay +90°',
                        icon: const Icon(Icons.rotate_90_degrees_cw),
                        color: Colors.white,
                        onPressed: () => setState(() {
                          _rotAdjust = (_rotAdjust + 90) % 360;
                        }),
                      ),
                    ],
                  ),
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
  final String text; const _Chip({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.55),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        )),
  );
}
