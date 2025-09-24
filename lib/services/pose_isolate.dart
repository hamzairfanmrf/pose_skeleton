// // lib/services/pose_isolate.dart
// import 'dart:isolate';
// import 'dart:typed_data';
// import 'dart:ui';
//
// import '../ml/movenet.dart';
// import '../ml/pose_types.dart';
//
// class PoseRequest {
//   final Uint8List rgbBytes; // model input RGB (e.g., 192x192x3 bytes)
//   final Size dummy;         // not used; kept for API compatibility
//   const PoseRequest(this.rgbBytes, this.dummy);
// }
//
// class PoseResponse {
//   final Pose pose;
//   const PoseResponse(this.pose);
// }
//
// class PoseIsolate {
//   Isolate? _isolate;
//   SendPort? _send;
//
//   Future<SendPort> start(Uint8List modelBytes, {int inputSize = 192, int threads = 4}) async {
//     final ready = ReceivePort();
//     _isolate = await Isolate.spawn(_entry, [ready.sendPort, modelBytes, inputSize, threads]);
//     _send = await ready.first as SendPort;
//     return _send!;
//   }
//
//   static Future<void> _entry(List initial) async {
//     final SendPort toMain = initial[0] as SendPort;
//     final Uint8List modelBytes = initial[1] as Uint8List;
//     final int inputSize = initial[2] as int;
//     final int threads = initial[3] as int;
//
//     final net = await MoveNet.fromBytes(modelBytes, inputSize: inputSize, threads: threads);
//
//     final port = ReceivePort();
//     toMain.send(port.sendPort);
//
//     await for (final msg in port) {
//       if (msg is List && msg.length == 2) {
//         final SendPort reply = msg[0];
//         final PoseRequest req = msg[1];
//         final pose = net.inferFromRgbBytes(req.rgbBytes, const Size(1, 1));
//         reply.send(PoseResponse(pose));
//       }
//     }
//   }
//
//   void dispose() {
//     _isolate?.kill(priority: Isolate.immediate);
//     _isolate = null;
//     _send = null;
//   }
// }
