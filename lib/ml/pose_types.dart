// lib/pose_types.dart
import 'package:flutter/material.dart';

class Keypoint {
  final String name;
  final Offset position; // in source/model space
  final double score;
  const Keypoint(this.name, this.position, this.score);
}

class Pose {
  final List<Keypoint> keypoints;
  const Pose(this.keypoints);
}

/// MoveNet keypoint order 0..16
const List<String> keypointNames = [
  'nose',            // 0
  'leftEye',         // 1
  'rightEye',        // 2
  'leftEar',         // 3
  'rightEar',        // 4
  'leftShoulder',    // 5
  'rightShoulder',   // 6
  'leftElbow',       // 7
  'rightElbow',      // 8
  'leftWrist',       // 9
  'rightWrist',      // 10
  'leftHip',         // 11
  'rightHip',        // 12
  'leftKnee',        // 13
  'rightKnee',       // 14
  'leftAnkle',       // 15
  'rightAnkle',      // 16
];

/// Standard skeleton edges for MoveNet
const List<List<String>> skeletonPairs = [
  // face/neck
  ['leftEye', 'rightEye'],
  ['leftEye', 'leftEar'],
  ['rightEye', 'rightEar'],
  ['nose', 'leftEye'],
  ['nose', 'rightEye'],
  // shoulders / torso
  ['leftShoulder', 'rightShoulder'],
  ['leftShoulder', 'leftElbow'],
  ['rightShoulder', 'rightElbow'],
  ['leftElbow', 'leftWrist'],
  ['rightElbow', 'rightWrist'],
  ['leftShoulder', 'leftHip'],
  ['rightShoulder', 'rightHip'],
  ['leftHip', 'rightHip'],
  // legs
  ['leftHip', 'leftKnee'],
  ['rightHip', 'rightKnee'],
  ['leftKnee', 'leftAnkle'],
  ['rightKnee', 'rightAnkle'],
];
