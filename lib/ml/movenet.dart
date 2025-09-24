
import 'dart:typed_data';
import 'dart:ui';
import 'package:image/image.dart' as img;
import 'package:pose_skeleton/ml/pose_types.dart';
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

class MoveNet {
  final int inputSize; // 192
  late final tfl.Interpreter _it;
  late final tfl.TensorType _inType;
  late final List<int> _outShape;

  MoveNet._(this.inputSize, this._it, this._inType, this._outShape);

  static Future<MoveNet> load(Uint8List modelBytes, {int inputSize = 192, int threads = 4}) async {
    final opts = tfl.InterpreterOptions()..threads = threads;
    final it = await tfl.Interpreter.fromBuffer(modelBytes, options: opts);

    // Ensure input shape is [1,H,W,3]
    final in0 = it.getInputTensor(0);
    final shp = List<int>.from(in0.shape);
    if (shp.length == 4 && (shp[1] != inputSize || shp[2] != inputSize || shp[3] != 3)) {
      it.resizeInputTensor(0, [1, inputSize, inputSize, 3]);
    }
    it.allocateTensors();

    final out0 = it.getOutputTensor(0);
    final outShape = List<int>.from(out0.shape);
    final inType = in0.type;

    // quick sanity
    if (outShape.length != 4 || outShape[0] != 1 || outShape[1] != 1 || outShape[2] != 17 || outShape[3] != 3) {
      throw StateError('Unexpected output shape: $outShape (expected [1,1,17,3])');
    }

    return MoveNet._(inputSize, it, inType, outShape);
  }

  // ---------- helpers (no helper package needed) ----------

  // Stretched resize to exactly inputSize x inputSize (like Android ResizeOp(192,192))
  img.Image _resizeToModel(img.Image src) =>
      img.copyResize(src, width: inputSize, height: inputSize, interpolation: img.Interpolation.linear);

  // float32 NHWC, normalized with mean/std = 127.5
  Uint8List _imageToByteListFloat32(img.Image image) {
    final floats = Float32List(1 * inputSize * inputSize * 3);
    final buf = floats.buffer.asFloat32List();
    int i = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final px = image.getPixel(x, y); // packed int
        final r = img.getRed(px).toDouble();
        final g = img.getGreen(px).toDouble();
        final b = img.getBlue(px).toDouble();
        buf[i++] = (r - 127.5) / 127.5;
        buf[i++] = (g - 127.5) / 127.5;
        buf[i++] = (b - 127.5) / 127.5;
      }
    }
    return floats.buffer.asUint8List();
  }

  // uint8 NHWC (no normalization)
  Uint8List _imageToByteListUint8(img.Image image) {
    final bytes = Uint8List(1 * inputSize * inputSize * 3);
    int i = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final px = image.getPixel(x, y);
        bytes[i++] = img.getRed(px);
        bytes[i++] = img.getGreen(px);
        bytes[i++] = img.getBlue(px);
      }
    }
    return bytes;
  }

  // ---------- public API ----------

  /// Run MoveNet on an ARGB image. Returns normalized keypoints (x,y in 0..1).
  Pose inferFromImage(img.Image argbImage) {
    // 1) resize (stretch) to model input
    final inputImg = _resizeToModel(argbImage);

    // 2) pack NHWC according to input tensor type
    final Uint8List inputBuffer = (_inType == tfl.TensorType.float32)
        ? _imageToByteListFloat32(inputImg)
        : _imageToByteListUint8(inputImg); // uint8 / float16 models usually use uint8 input

    // 3) run
    // Output is [1,1,17,3]
    final output = List.generate(1, (_) => List.generate(1, (_) => List.generate(17, (_) => List.filled(3, 0.0))));
    _it.run(inputBuffer, output);

    // 4) parse normalized (y, x, score)
    final out = output as List;
    final kp = <Keypoint>[];
    for (int i = 0; i < 17; i++) {
      final y = (out[0][0][i][0] as num).toDouble();
      final x = (out[0][0][i][1] as num).toDouble();
      final s = (out[0][0][i][2] as num).toDouble();
      kp.add(Keypoint(keypointNames[i], Offset(x, y), s));
    }
    return Pose(kp);
  }

  void close() => _it.close();
}
