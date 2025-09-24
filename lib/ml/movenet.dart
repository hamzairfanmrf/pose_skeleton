// lib/ml/movenet.dart
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:pose_skeleton/ml/pose_types.dart';
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

class MoveNet {
  final int inputSize; // 192 or 256
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

    // If model has a placeholder [1,1,1,3], resize; otherwise respect its size.
    final in0 = it.getInputTensor(0);
    final shp = List<int>.from(in0.shape);
    final isPlaceholder = shp.length == 4 && shp[1] == 1 && shp[2] == 1 && shp[3] == 3;
    final isConcrete    = shp.length == 4 && shp[1] > 1 && shp[2] > 1 && shp[3] == 3;

    if (isPlaceholder) {
      it.resizeInputTensor(0, [1, inputSize, inputSize, 3]);
    } else if (isConcrete) {
      // lock to model's native size
      inputSize = shp[1];
    } else {
      throw StateError('Unexpected input tensor shape: $shp');
    }

    it.allocateTensors();

    // Debug: print tensors
    for (var i = 0; i < it.getInputTensors().length; i++) {
      final t = it.getInputTensors()[i];
      debugPrint('Input $i -> name:${t.name} shape:${t.shape} type:${t.type}');
    }
    for (var i = 0; i < it.getOutputTensors().length; i++) {
      final t = it.getOutputTensors()[i];
      debugPrint('Output $i -> name:${t.name} shape:${t.shape} type:${t.type}');
    }

    // Expect SinglePose head [1,1,17,3]
    final outShape = List<int>.from(it.getOutputTensor(0).shape);
    if (!(outShape.length == 4 && outShape[0] == 1 && outShape[1] == 1 && outShape[2] == 17 && outShape[3] == 3)) {
      throw StateError('Model output is $outShape (expected [1,1,17,3]). Wrong model file.');
    }

    final m = MoveNet._(inputSize, it);
    m._inTensor = it.getInputTensor(0);
    m._inType   = m._inTensor.type; // float32 / uint8 / int8
    m._outShape = outShape;
    return m;
  }

  /// rgbBytes: packed RGB of size (inputSize * inputSize * 3).
  /// Returns normalized keypoints (x,y in 0..1; score 0..1).
  Pose inferFromRgbBytes(Uint8List rgbBytes, Size _) {
    final H = inputSize, W = inputSize;

    // Build 4D input matching the tensor type
    Object input4d;

    switch (_inType) {
      case tfl.TensorType.float32:
      // Normalize to [0..1] and send as nested doubles
        final floats = Float32List(rgbBytes.length);
        for (int i = 0; i < rgbBytes.length; i++) {
          floats[i] = rgbBytes[i] / 255.0;
        }
        input4d = List.generate(
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
        break;

      case tfl.TensorType.uint8:
      // Feed raw bytes (0..255) as nested ints (no normalization)
        input4d = List.generate(
          1,
              (_) => List.generate(
            H,
                (y) => List.generate(
              W,
                  (x) {
                final base = (y * W + x) * 3;
                return <int>[
                  rgbBytes[base + 0],
                  rgbBytes[base + 1],
                  rgbBytes[base + 2],
                ];
              },
            ),
          ),
        );
        break;

      case tfl.TensorType.int8:
      // Quantized int8: apply quantization params (scale/zeroPoint)
        final q = _inTensor.params; // QuantizationParams
        final scale = (q.scale == 0) ? 1.0 : q.scale;
        final zp = q.zeroPoint; // usually around -128..127
        final ints = Int8List(rgbBytes.length);
        for (int i = 0; i < rgbBytes.length; i++) {
          final qv = (rgbBytes[i] / scale + zp).round();
          ints[i] = qv.clamp(-128, 127);
        }
        input4d = List.generate(
          1,
              (_) => List.generate(
            H,
                (y) => List.generate(
              W,
                  (x) {
                final base = (y * W + x) * 3;
                return <int>[
                  ints[base + 0],
                  ints[base + 1],
                  ints[base + 2],
                ];
              },
            ),
          ),
        );
        break;

      default:
        throw UnsupportedError('Unsupported input type: $_inType');
    }

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

      // Debug
      debugPrint(
        '${keypointNames[i]} -> x:${x.toStringAsFixed(3)} y:${y.toStringAsFixed(3)} score:${s.toStringAsFixed(2)}',
      );
    }
    debugPrint('--- End of keypoints ---');

    return Pose(kp);
  }

  void close() => _interpreter.close();
}
