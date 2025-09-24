import 'dart:typed_data';
import 'dart:ui';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

class Keypoint {
  final String name;
  final Offset position; // normalized [0..1] (x,y)
  final double score;
  Keypoint(this.name, this.position, this.score);
}

class Pose {
  final List<Keypoint> keypoints;
  Pose(this.keypoints);
}

const keypointNames = <String>[
  'nose','leftEye','rightEye','leftEar','rightEar',
  'leftShoulder','rightShoulder','leftElbow','rightElbow',
  'leftWrist','rightWrist','leftHip','rightHip',
  'leftKnee','rightKnee','leftAnkle','rightAnkle',
];

