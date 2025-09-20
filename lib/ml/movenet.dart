// lib/ml/movenet.dart
import 'dart:typed_data';
import 'dart:ui';
import 'package:pose_skeleton/ml/pose_types.dart';
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

class MoveNet {
  final int inputSize; // 192 (Lightning) or 256 (Thunder)
  late final tfl.Interpreter _interpreter;
  late tfl.Tensor _inTensor;
  late tfl.TensorType _inType;
  late List<int> _outShape; // e.g. [1,1,17,3] or [1,6,56]

  MoveNet._(this.inputSize, this._interpreter);

  /// Create an interpreter from raw model bytes (works in isolates).
  static Future<MoveNet> fromBytes(
      Uint8List bytes, {
        int inputSize = 192,
      }) async {
    final interpreter = await tfl.Interpreter.fromBuffer(
      bytes,
      options: tfl.InterpreterOptions()..threads = 4,
    );

    // Ensure expected NHWC input shape: [1, inputSize, inputSize, 3]
    final input = interpreter.getInputTensor(0);
    final shp = List<int>.from(input.shape);
    final needsResize = shp.length == 4 &&
        (shp[1] != inputSize || shp[2] != inputSize || shp[3] != 3);
    final looksPlaceholder = shp.length == 4 && shp[1] == 1 && shp[2] == 1 && shp[3] == 3;

    if (needsResize || looksPlaceholder) {
      interpreter.resizeInputTensor(0, [1, inputSize, inputSize, 3]);
    }
    // allocateTensors() is synchronous in tflite_flutter
    interpreter.allocateTensors();

    final m = MoveNet._(inputSize, interpreter);
    m._inTensor = interpreter.getInputTensor(0);
    m._inType = m._inTensor.type; // TensorType enum in ^0.11.x
    m._outShape = List<int>.from(interpreter.getOutputTensor(0).shape);
    return m;
  }

  /// rgbBytes: packed RGB bytes of size inputSize*inputSize*3
  Pose inferFromRgbBytes(Uint8List rgbBytes, Size sourceSize) {
    final output = _allocOutputBuffer();

    // Feed input according to tensor type
    switch (_inType) {
      case tfl.TensorType.float32: {
        final floats = Float32List(rgbBytes.length);
        for (int i = 0; i < rgbBytes.length; i++) {
          floats[i] = rgbBytes[i] / 255.0;
        }
        _interpreter.run(floats, output);
        break;
      }
      case tfl.TensorType.uint8: {
        _interpreter.run(rgbBytes, output);
        break;
      }
      case tfl.TensorType.int8: {
        // Quantized int8 model
        final q = _inTensor.params;
        final scale = (q.scale == 0) ? 1.0 : q.scale;
        final zp = q.zeroPoint; // usually -128..127
        final ints = Int8List(rgbBytes.length);
        for (int i = 0; i < rgbBytes.length; i++) {
          final qv = (rgbBytes[i] / scale + zp).round();
          ints[i] = qv.clamp(-128, 127);
        }
        _interpreter.run(ints, output);
        break;
      }
      default:
        throw UnsupportedError('Unsupported input type: $_inType');
    }

    // Parse output
    if (_isSinglePose(_outShape)) {
      // [1,1,17,3] => (y, x, score)
      final out = output as List;
      final kp = <Keypoint>[];
      // inside _isSinglePose branch
      for (int i = 0; i < 17; i++) {
        final y = out[0][0][i][0] as double;
        final x = out[0][0][i][1] as double;
        final s = out[0][0][i][2] as double;
        kp.add(Keypoint(
          keypointNames[i],
          Offset(x, y), // keep normalized [0..1]
          s,
        ));
      }

      return Pose(kp);
    }
 else if (_isMultiPose(_outShape)) {
      // [1, N, 56] => up to N persons; 56 = 17*3 + 5 meta
      final out = output as List;
      final persons = out[0] as List;

      // Choose best person by overall score (assume last index 55)
      int bestIdx = 0;
      double bestScore = -1;
      for (int i = 0; i < persons.length; i++) {
        final row = persons[i] as List;
        if (row.isEmpty) continue;
        final score = (row.length >= 56) ? (row[55] as double) : 0.0;
        if (score > bestScore) { bestScore = score; bestIdx = i; }
      }

      final row = persons[bestIdx] as List;
      final kp = <Keypoint>[];
      for (int j = 0; j < 17; j++) {
        final y = row[j * 3 + 0] as double;
        final x = row[j * 3 + 1] as double;
        final s = row[j * 3 + 2] as double;
        kp.add(Keypoint(
          keypointNames[j],
          Offset(x, y), // normalized
          s,
        ));
      }

      return Pose(kp);
    } else {
      throw StateError('Unknown MoveNet output shape: $_outShape');
    }
  }

  // ----- helpers -----

  bool _isSinglePose(List<int> s) =>
      s.length == 4 && s[0] == 1 && s[1] == 1 && s[2] == 17 && s[3] == 3;

  bool _isMultiPose(List<int> s) =>
      s.length == 3 && s[0] == 1 && s[2] == 56; // [1, N, 56]

  Object _allocOutputBuffer() {
    if (_isSinglePose(_outShape)) {
      return List.generate(
        1, (_) => List.generate(1, (_) => List.generate(17, (_) => List.filled(3, 0.0))),
      );
    } else if (_isMultiPose(_outShape)) {
      final n = _outShape[1]; // number of detections (e.g., 6)
      return List.generate(1, (_) => List.generate(n, (_) => List.filled(56, 0.0)));
    } else {
      // Generic fallback (will error on parse if truly unknown)
      return List.generate(
        1, (_) => List.generate(1, (_) => List.generate(17, (_) => List.filled(3, 0.0))),
      );
    }
  }
}
