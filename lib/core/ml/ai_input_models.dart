import 'dart:math' as math;

import 'dart:typed_data';

import 'health_ai_service.dart';

// =============================================================================
// MODULE A: ECG  [1, 187, 1] -> [1, 5]  (N, S, V, F, Q)
// =============================================================================
class EcgModelInput {
  final List<double> samples; // 187 values, 0.0 - 1.0

  EcgModelInput(this.samples) : assert(samples.length == 187);

  static const List<String> classDescriptions = <String>[
    'N (Normal Beat)',
    'S (Supraventricular)',
    'V (Ventricular / PVC)',
    'F (Fusion Beat)',
    'Q (Unclassified)',
  ];

  /// Rough heart-rate estimate from R-peak spacing (MIT-BIH is sampled at
  /// 125 Hz). With a single isolated beat there is no second peak, so 72 bpm
  /// is returned as a neutral default.
  int estimateBpm() {
    double maxV = 0;
    for (final double v in samples) {
      if (v > maxV) maxV = v;
    }
    if (maxV <= 0) return 72;
    final double thr = maxV * 0.7;
    final List<int> peaks = <int>[];
    for (int i = 1; i < samples.length - 1; i++) {
      if (samples[i] >= thr && samples[i] >= samples[i - 1] && samples[i] > samples[i + 1]) {
        if (peaks.isEmpty || i - peaks.last > 20) peaks.add(i);
      }
    }
    if (peaks.length < 2) return 72;
    final double avg = (peaks.last - peaks.first) / (peaks.length - 1);
    return (60.0 * 125.0 / avg).round().clamp(40, 180);
  }

  /// Synthetic stand-in beat per MIT-BIH class (0=N, 1=S, 2=V, 3=F, 4=Q).
  /// For real tests, paste a beat from mitbih_test.csv into the text box.
  static List<double> generateMitBihSample(int classIdx) {
    final rnd = math.Random(42 + classIdx);
    final List<double> wave = List<double>.filled(187, 0.15);
    for (int i = 0; i < 187; i++) {
      double v = 0.15;
      switch (classIdx) {
        case 1: // S: early narrow beat, no clear P wave
          if (i >= 20 && i <= 28) v = 1.0 - ((i - 24).abs() * 0.2);
          if (i >= 50 && i <= 70) v = 0.38 - ((i - 60).abs() * 0.015);
          break;
        case 2: // V / PVC: wide tall complex, inverted T
          if (i >= 30 && i <= 60) v = 0.95 - ((i - 45).abs() * 0.05);
          if (i >= 75 && i <= 100) v = 0.05;
          break;
        case 3: // F: fusion, wide but lower amplitude
          if (i >= 32 && i <= 54) v = 0.8 - ((i - 43).abs() * 0.05);
          if (i >= 70 && i <= 90) v = 0.35;
          break;
        case 4: // Q: noisy / unclassifiable
          v = 0.3 + 0.25 * math.sin(i / 6.0);
          break;
        default: // N: P, QRS, T
          if (i >= 15 && i <= 25) v = 0.35;
          if (i >= 35 && i <= 45) v = 1.0 - ((i - 40).abs() * 0.16);
          if (i >= 65 && i <= 85) v = 0.45 - ((i - 75).abs() * 0.02);
      }
      v += (rnd.nextDouble() - 0.5) * 0.02;
      wave[i] = double.parse(v.clamp(0.0, 1.0).toStringAsFixed(4));
    }
    return wave;
  }

  // Kept for older callers.
  static List<double> generatePreset(String presetType) {
    if (presetType == 'Arrhythmia (PVC)') return generateMitBihSample(2);
    if (presetType == 'Space Radiation Stress') return generateMitBihSample(1);
    return generateMitBihSample(0);
  }
}

class EcgPredictionResult {
  final List<double> probabilities;
  final double anomalyScore;
  final String engineUsed;
  const EcgPredictionResult(this.probabilities, this.anomalyScore, this.engineUsed);
}

// =============================================================================
// MODULE B: Cardiovascular  [1, 12] -> [1, 1]
// =============================================================================
class CardioModelInput {
  final double ageYears;
  final int gender; // 1 = Female, 2 = Male (same as the training data)
  final double heightCm;
  final double weightKg;
  final double apHi; // systolic
  final double apLo; // diastolic
  final int cholesterol; // 1..3
  final int gluc; // 1..3
  final int smoke; // 0/1
  final int alco; // 0/1
  final int active; // 0/1

  CardioModelInput({
    required this.ageYears,
    required this.gender,
    required this.heightCm,
    required this.weightKg,
    required this.apHi,
    required this.apLo,
    required this.cholesterol,
    required this.gluc,
    required this.smoke,
    required this.alco,
    required this.active,
  });

  double get bmi {
    final double h = heightCm / 100.0;
    return h <= 0 ? 0.0 : weightKg / (h * h);
  }

  /// [age, gender, height, weight, ap_hi, ap_lo, cholesterol, gluc, smoke, alco, active, bmi]
  List<double> get rawFeatures => <double>[
        ageYears,
        gender.toDouble(),
        heightCm,
        weightKg,
        apHi,
        apLo,
        cholesterol.toDouble(),
        gluc.toDouble(),
        smoke.toDouble(),
        alco.toDouble(),
        active.toDouble(),
        bmi,
      ];
}

class CardioPredictionResult {
  final double risk;
  final List<double> standardizedZ;
  final String engineUsed;
  const CardioPredictionResult(this.risk, this.standardizedZ, this.engineUsed);
}

// =============================================================================
// MODULE C: Posture
//  - camera photo: real model, input [1, 224, 224, 3] RGB 0..255
//  - angle sliders only: simple angle-based estimate (no camera frame)
// =============================================================================
class PostureModelInput {
  final double neckDevDeg;
  final double spineCurvDeg;
  final List<double>? rgbTensor; // 224*224*3 floats, from a camera photo

  PostureModelInput({
    required this.neckDevDeg,
    required this.spineCurvDeg,
    this.rgbTensor,
  });
}

class PosturePredictionResult {
  final double risk;
  final String engineUsed;
  const PosturePredictionResult(this.risk, this.engineUsed);
}

// =============================================================================
// Service used by the screen (runs the real TFLite models)
// =============================================================================
class NasaAiService {
  static final HealthAiService _ai = HealthAiService();
  static Future<void>? _loading;

  static bool get isLiveKerasConnected => false;

  static Future<void> _ensureLoaded() {
    return _loading ??= _ai.load().catchError((Object e) {
      _loading = null; // allow retry
      throw e;
    });
  }

  static Future<EcgPredictionResult> runEcgModel(EcgModelInput input) async {
    await _ensureLoaded();
    final List<double> probs = _ai.runEcg(input.samples);
    return EcgPredictionResult(probs, (1.0 - probs[0]).clamp(0.0, 1.0).toDouble(),
        'TFLITE ecg_heartbeat');
  }

  static Future<CardioPredictionResult> runCardioModel(CardioModelInput input) async {
    await _ensureLoaded();
    final r = _ai.runCardio(input.rawFeatures);
    return CardioPredictionResult(r.risk, r.z, 'TFLITE cardiovascular');
  }

  static Future<PosturePredictionResult> runPostureModel(PostureModelInput input) async {
    final List<double>? frame = input.rgbTensor;
    if (frame != null) {
      await _ensureLoaded();
      return PosturePredictionResult(_ai.runPosture(frame), 'TFLITE posture (camera frame)');
    }
    // No camera frame: estimate from the two angles (ok=15/10 deg, bad=45/35 deg).
    final double neck = ((input.neckDevDeg - 15.0) / 30.0).clamp(0.0, 1.0);
    final double spine = ((input.spineCurvDeg - 10.0) / 25.0).clamp(0.0, 1.0);
    final double risk = (0.1 + 0.9 * (0.5 * neck + 0.5 * spine)).clamp(0.0, 1.0);
    return PosturePredictionResult(risk, 'ANGLE ESTIMATE (no camera frame)');
  }

  /// Photo bytes (JPEG/PNG) -> 224x224 RGB tensor for the posture model.
  static Future<List<double>> photoToTensor(Uint8List bytes) =>
      HealthAiService.imageBytesToTensor(bytes);
}
