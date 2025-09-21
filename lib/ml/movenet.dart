// lib/ml/movenet.dart
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:pose_skeleton/ml/pose_types.dart';
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

class MoveNet {
  final int inputSize; // 192
  late final tfl.Interpreter _interpreter;
  late tfl.Tensor _inTensor;
  late tfl.TensorType _inType;
  late List<int> _outShape;

  MoveNet._(this.inputSize, this._interpreter);

  static Future<MoveNet> fromBytes(
      Uint8List bytes, {
        int inputSize = 192,
        int threads = 4,
      }) async {
    final options = tfl.InterpreterOptions()..threads = threads;
    final it = await tfl.Interpreter.fromBuffer(bytes, options: options);

    // Resize input if needed
    final inp = it.getInputTensor(0);
    final shp = List<int>.from(inp.shape);
    if (shp.length == 4 &&
        (shp[1] != inputSize || shp[2] != inputSize || shp[3] != 3)) {
      it.resizeInputTensor(0, [1, inputSize, inputSize, 3]);
    }
    it.allocateTensors();

    // Print tensor info
    for (var i = 0; i < it.getInputTensors().length; i++) {
      final t = it.getInputTensors()[i];
      debugPrint(
          'Input $i -> name:${t.name} shape:${t.shape} type:${t.type}');
    }
    for (var i = 0; i < it.getOutputTensors().length; i++) {
      final t = it.getOutputTensors()[i];
      debugPrint(
          'Output $i -> name:${t.name} shape:${t.shape} type:${t.type}');
    }

    // Sanity checks
    final inT = it.getInputTensor(0);
    final outT = it.getOutputTensor(0);
    final inShape = List<int>.from(inT.shape);
    final outShape = List<int>.from(outT.shape);

    if (!(inShape.length == 4 &&
        inShape[1] == inputSize &&
        inShape[2] == inputSize &&
        inShape[3] == 3)) {
      throw StateError(
          'Model input is $inShape (expected [1,$inputSize,$inputSize,3]). Wrong model file.');
    }
    if (!(outShape.length == 4 &&
        outShape[0] == 1 &&
        outShape[1] == 1 &&
        outShape[2] == 17 &&
        outShape[3] == 3)) {
      throw StateError(
          'Model output is $outShape (expected [1,1,17,3]). Wrong model file.');
    }

    final m = MoveNet._(inputSize, it);
    m._inTensor = inT;
    m._inType = inT.type;
    m._outShape = outShape;
    return m;
  }

  Pose inferFromRgbBytes(Uint8List rgbBytes, Size _) {
    // Convert packed RGB bytes -> float32 [0..1]
    final floats = Float32List(rgbBytes.length);
    for (int i = 0; i < rgbBytes.length; i++) {
      floats[i] = rgbBytes[i] / 255.0;
    }

    // Build nested 4D input [1, H, W, 3]
    final int H = inputSize;
    final int W = inputSize;
    final input4d = List.generate(
      1,
          (_) => List.generate(
        H,
            (y) => List.generate(
          W,
              (x) {
            final base = (y * W + x) * 3;
            return <double>[
              floats[base + 0],
              floats[base + 1],
              floats[base + 2],
            ];
          },
        ),
      ),
    );

    // Output buffer for [1,1,17,3]
    final output = List.generate(
      1,
          (_) => List.generate(
        1,
            (_) => List.generate(
          17,
              (_) => List.filled(3, 0.0),
        ),
      ),
    );

    _interpreter.run(input4d, output);

    // Parse normalized (y, x, score)
    final out = output as List;
    final kp = <Keypoint>[];
    for (int i = 0; i < 17; i++) {
      final y = out[0][0][i][0] as double;
      final x = out[0][0][i][1] as double;
      final s = out[0][0][i][2] as double;
      kp.add(Keypoint(keypointNames[i], Offset(x, y), s));

      // 🔴 Debug print each keypoint
      debugPrint(
          '${keypointNames[i]} -> x:${x.toStringAsFixed(3)} y:${y.toStringAsFixed(3)} score:${s.toStringAsFixed(2)}');
    }
    debugPrint('--- End of keypoints ---');

    return Pose(kp);
  }

  void close() => _interpreter.close();
}
