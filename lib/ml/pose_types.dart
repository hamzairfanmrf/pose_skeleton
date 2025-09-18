import 'dart:ui';

class Keypoint {
  final String name;
  final Offset position; // image-space in preview coordinates
  final double score; // 0..1
  const Keypoint(this.name, this.position, this.score);
}

class Pose {
  final List<Keypoint> keypoints; // 17 keypoints
  const Pose(this.keypoints);
}

/// MoveNet keypoint order
const keypointNames = [
  'nose', 'leftEye', 'rightEye', 'leftEar', 'rightEar',
  'leftShoulder', 'rightShoulder', 'leftElbow', 'rightElbow',
  'leftWrist', 'rightWrist', 'leftHip', 'rightHip',
  'leftKnee', 'rightKnee', 'leftAnkle', 'rightAnkle',
];

/// Pairs for skeleton lines
const skeletonPairs = [
  ['leftShoulder','rightShoulder'], ['leftHip','rightHip'],
  ['leftShoulder','leftElbow'], ['leftElbow','leftWrist'],
  ['rightShoulder','rightElbow'], ['rightElbow','rightWrist'],
  ['leftHip','leftKnee'], ['leftKnee','leftAnkle'],
  ['rightHip','rightKnee'], ['rightKnee','rightAnkle'],
  ['leftShoulder','leftHip'], ['rightShoulder','rightHip'],
  ['nose','leftEye'], ['nose','rightEye'], ['leftEye','leftEar'], ['rightEye','rightEar'],
];