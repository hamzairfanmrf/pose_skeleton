import 'package:flutter/material.dart';
import 'package:pose_skeleton/pages/camera_page.dart';
import 'package:pose_skeleton/pages/ml_kit_pose_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PoseApp());
}

class PoseApp extends StatelessWidget {
  const PoseApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pose Skeleton',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const MlkitPosePage(),
    );
  }
}