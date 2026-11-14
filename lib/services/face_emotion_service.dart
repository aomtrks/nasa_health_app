// astronaut_health_monitor/lib/services/face_emotion_service.dart
//
// pubspec.yaml:
//   dependencies:
//     google_mlkit_face_detection: ^0.11.0   # use the latest version
//     camera: ^0.10.5
//
// ML Kit runs fully on-device (offline). It does NOT output emotions directly;
// it gives smile probability, eye-open probabilities and head angles.
// This service turns them into simple wellbeing indicators (0.0 - 1.0).

import 'dart:math';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceStateResult {
  final double smile; // 0 = not smiling, 1 = smiling
  final double eyeOpen; // 0 = closed, 1 = wide open
  final double fatigue; // 0 = alert, 1 = drowsy
  final double headOffset; // 0 = head straight, 1 = strongly tilted/turned
  final double stress; // 0..1 neurological/psychological region indicator
  const FaceStateResult({
    required this.smile,
    required this.eyeOpen,
    required this.fatigue,
    required this.headOffset,
    required this.stress,
  });
}

class FaceEmotionService {
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true, // needed for smile + eye-open probabilities
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.2,
    ),
  );

  // Exponential smoothing so blinks / single bad frames don't spike the score.
  static const double _alpha = 0.2;
  double? _smile, _eyeOpen, _headOffset;

  double _ema(double? prev, double value) =>
      prev == null ? value : prev + _alpha * (value - prev);

  /// Call with each camera frame (InputImage.fromBytes / fromFilePath).
  /// Returns null if no face is visible.
  Future<FaceStateResult?> analyze(InputImage image) async {
    final faces = await _detector.processImage(image);
    if (faces.isEmpty) return null;

    // Use the largest face (the astronaut closest to the camera).
    final face = faces.reduce(
      (a, b) =>
          a.boundingBox.width * a.boundingBox.height >=
                  b.boundingBox.width * b.boundingBox.height
              ? a
              : b,
    );

    final rawSmile = face.smilingProbability ?? 0.5;
    final l = face.leftEyeOpenProbability;
    final r = face.rightEyeOpenProbability;
    final rawEye = (l != null && r != null) ? (l + r) / 2 : 0.5;

    final x = (face.headEulerAngleX ?? 0).abs(); // nod up/down
    final y = (face.headEulerAngleY ?? 0).abs(); // turn left/right
    final z = (face.headEulerAngleZ ?? 0).abs(); // tilt
    final rawHead = (max(x, max(y, z)) / 40.0).clamp(0.0, 1.0);

    _smile = _ema(_smile, rawSmile);
    _eyeOpen = _ema(_eyeOpen, rawEye);
    _headOffset = _ema(_headOffset, rawHead);

    final fatigue = (1.0 - _eyeOpen!).clamp(0.0, 1.0);
    // Heuristic weights - tune with real data/expert input.
    final stress = (0.4 * (1.0 - _smile!) + 0.4 * fatigue + 0.2 * _headOffset!)
        .clamp(0.0, 1.0);

    return FaceStateResult(
      smile: _smile!,
      eyeOpen: _eyeOpen!,
      fatigue: fatigue,
      headOffset: _headOffset!,
      stress: stress,
    );
  }

  void reset() => _smile = _eyeOpen = _headOffset = null;

  Future<void> dispose() => _detector.close();
}
