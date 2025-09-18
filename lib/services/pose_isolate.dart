import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';
import '../ml/movenet.dart';
import '../ml/pose_types.dart';

class PoseRequest {
  final Uint8List rgbBytes; // packed RGB
  final Size sourceSize;
  PoseRequest(this.rgbBytes, this.sourceSize);
}

class PoseResponse {
  final Pose pose;
  PoseResponse(this.pose);
}

class PoseIsolate {
  Isolate? _iso;
  SendPort? _send;

  // Pass model bytes from main isolate
  Future<SendPort> start(Uint8List modelBytes, {int inputSize = 192}) async {
    final recv = ReceivePort();
    _iso = await Isolate.spawn(_entry, [recv.sendPort, modelBytes, inputSize],
        debugName: 'pose_isolate');
    _send = await recv.first as SendPort;
    return _send!;
  }

  static Future<void> _entry(List initial) async {
    final SendPort toMain = initial[0] as SendPort;
    final Uint8List modelBytes = initial[1] as Uint8List;
    final int inputSize = initial[2] as int;

    // Build MoveNet from bytes (no asset bundle required in isolate)
    final moveNet = await MoveNet.fromBytes(modelBytes, inputSize: inputSize);

    final port = ReceivePort();
    toMain.send(port.sendPort);

    await for (final msg in port) {
      if (msg is List && msg.length == 2) {
        final SendPort reply = msg[0];
        final PoseRequest req = msg[1];
        final pose = moveNet.inferFromRgbBytes(req.rgbBytes, req.sourceSize);
        reply.send(PoseResponse(pose));
      }
    }
  }
}
