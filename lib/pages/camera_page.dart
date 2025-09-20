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

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final cam = CameraService(preset: ResolutionPreset.medium);
  late final PoseIsolate iso;
  Size? latestSourceSize;
  SendPort? isoPort;
  final fps = FpsCounter();
  Pose? currentPose;
  bool performanceMode = true;
  int downsample = 2;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await cam.init();
    final ByteData bd = await rootBundle.load('assets/models/movenet_lightning.tflite');
    final Uint8List modelBytes = bd.buffer.asUint8List();

    iso = PoseIsolate();
    isoPort = await iso.start(modelBytes, inputSize: 192);

    await cam.start(downsample: performanceMode ? downsample : 1, outSize: 192);
    _sub = cam.frames.listen(_onFrame);

    setState(() {});
  }

  Future<void> _onFrame(FrameData frame) async {
    latestSourceSize = Size(frame.size.toDouble(), frame.size.toDouble()); // ✅ 192x192

    final recv = ReceivePort();
    isoPort!.send([
      recv.sendPort,
      PoseRequest(frame.rgb, latestSourceSize!), // MoveNet expects this space too
    ]);
    final resp = await recv.first as PoseResponse;

    setState(() {
      currentPose = resp.pose; // (apply smoothing if you use it)
      fps.tick();
    });
  }


  @override
  void dispose() {
    _sub?.cancel();
    cam.stop();
    cam.dispose();
    super.dispose();
  }
  int rotationImageToDisplay(CameraController c) {
    final sensor = c.description.sensorOrientation; // e.g., 90 or 270

    final map = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final device = map[c.value.deviceOrientation] ?? 0;

    final isFront = c.description.lensDirection == CameraLensDirection.front;
    // delta from image (sensor) to what CameraPreview shows
    return isFront ? (sensor + device) % 360 : (sensor - device + 360) % 360;
  }

  // in _CameraPageState
  int _rotAdjust = 0; // tap the 🔄 button to add +90 each time

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
          final box = constraints.biggest;

          final pv = ctrl.value.previewSize!;
          final previewW = pv.height;
          final previewH = pv.width;

          return Stack(
            fit: StackFit.expand,
            children: [
              // FULL-SCREEN preview, cover
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

              // SKELETON overlay (expects normalized coords)
              CustomPaint(
                size: box,
                painter: PosePainter(
                  currentPose,
                  displaySize: box,
                  rotationDeg: rot,
                  mirrorX: isFront,
                  conf: 0.40,
                ),
              ),

              // === UI chips and a rotation calibrator ===
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _Chip(text: 'MoveNet Lightning'),
                      const SizedBox(width: 8),
                      _Chip(text: '${fps.fps.toStringAsFixed(1)} FPS'),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Rotate overlay +90°',
                        icon: const Icon(Icons.rotate_90_degrees_cw),
                        onPressed: () {
                          setState(() { _rotAdjust = (_rotAdjust + 90) % 360; });
                        },
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
      color: Colors.black.withOpacity(0.5),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
  );
}
