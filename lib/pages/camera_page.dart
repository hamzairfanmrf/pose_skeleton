import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
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
    if (isoPort == null) return;
    final recv = ReceivePort();
    isoPort!.send([recv.sendPort, PoseRequest(frame.rgb, Size(frame.srcW.toDouble(), frame.srcH.toDouble()))]);
    final resp = await recv.first as PoseResponse;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!cam.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: Stack(
        children: [
          CameraPreview(cam.controller!),
          Positioned.fill(child: CustomPaint(painter: PosePainter(currentPose))),
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
                    onPressed: () async {
                      setState(() => performanceMode = !performanceMode);
                      await cam.stop();
                      await cam.start(downsample: performanceMode ? downsample : 1, outSize: 192);
                    },
                    icon: Icon(performanceMode ? Icons.speed : Icons.high_quality),
                    tooltip: performanceMode ? 'Performance Mode' : 'Quality Mode',
                  ),
                ],
              ),
            ),
          ),
        ],
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
