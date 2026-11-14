import 'dart:math' as math;
import 'dart:typed_data';

/// Model A: ECG Input [1, 187, 1] -> Output [1, 5]
class EcgModelInput {
  final List<double> samples; // Uzunluk 187, değerler 0.0 - 1.0 arası

  EcgModelInput(this.samples) : assert(samples.length == 187);

  /// Modelin beklediği float32 [1, 187, 1] düzleştirilmiş (flattened) tensör
  Float32List toFloat32Tensor() {
    final buffer = Float32List(187);
    for (int i = 0; i < 187; i++) {
      buffer[i] = samples[i].clamp(0.0, 1.0);
    }
    return buffer;
  }

  /// Test ve simülasyon için 187 örnekli sentetik EKG dalgası üretici
  static List<double> generatePreset(String presetType) {
    final List<double> wave = List.filled(187, 0.15);
    final rnd = math.Random(42);

    for (int i = 0; i < 187; i++) {
      double t = i / 187.0;
      double val = 0.2;

      // R-Peak (Kalp atım zirvesi)
      if (i >= 35 && i <= 45) {
        val = 1.0 - ((i - 40).abs() * 0.16);
      } else if (i >= 15 && i <= 25) {
        // P dalgası
        val = 0.35;
      } else if (i >= 65 && i <= 85) {
        // T dalgası
        val = 0.45 - ((i - 75).abs() * 0.02);
      }

      if (presetType == 'Arrhythmia (PVC)') {
        if (i >= 95 && i <= 115) val = 0.88 - ((i - 105).abs() * 0.07);
        val += (rnd.nextDouble() - 0.5) * 0.08;
      } else if (presetType == 'Space Radiation Stress') {
        val = (val + 0.15 * math.sin(t * 25)).clamp(0.0, 1.0);
      }

      wave[i] = double.parse(val.clamp(0.0, 1.0).toStringAsFixed(4));
    }
    return wave;
  }
}

/// Model B: Cardiovascular Input [1, 12] -> Output [1, 1]
class CardioModelInput {
  final double ageYears;
  final int gender; // 0: Female, 1: Male
  final double heightCm;
  final double weightKg;
  final double systolicBp;
  final double diastolicBp;
  final int cholesterol; // 1: Normal, 2: Above Normal, 3: Well Above Normal
  final int glucose; // 1: Normal, 2: Above Normal, 3: Well Above Normal
  final int smoke; // 0 or 1
  final int alcohol; // 0 or 1
  final int active; // 0 or 1

  CardioModelInput({
    required this.ageYears,
    required this.gender,
    required this.heightCm,
    required this.weightKg,
    required this.systolicBp,
    required this.diastolicBp,
    required this.cholesterol,
    required this.glucose,
    required this.smoke,
    required this.alcohol,
    required this.active,
  });

  double get bmi {
    final heightM = heightCm / 100.0;
    if (heightM <= 0) return 0.0;
    return weightKg / (heightM * heightM);
  }

  /// Ham 12 özellik vektörü:
  /// [age, gender, height, weight, ap_hi, ap_lo, cholesterol, gluc, smoke, alco, active, bmi]
  List<double> get rawFeatures => [
        ageYears,
        gender.toDouble(),
        heightCm,
        weightKg,
        systolicBp,
        diastolicBp,
        cholesterol.toDouble(),
        glucose.toDouble(),
        smoke.toDouble(),
        alcohol.toDouble(),
        active.toDouble(),
        bmi,
      ];

  /// JSON Scaler (mean & std) ile standardize edilmiş float32 [1, 12] tensör
  Float32List toStandardizedFloat32Tensor({
    List<double>? mean,
    List<double>? std,
  }) {
    // AI ekibinin JSON scaler dosyasından gelecek varsayılan mean/std değerleri
    final defaultMean = mean ??
        [53.3, 0.35, 164.3, 74.2, 128.8, 96.6, 1.36, 1.22, 0.08, 0.05, 0.80, 27.5];
    final defaultStd = std ??
        [6.7, 0.47, 8.2, 14.3, 154.0, 188.4, 0.68, 0.57, 0.28, 0.22, 0.39, 6.0];

    final raw = rawFeatures;
    final tensor = Float32List(12);
    for (int i = 0; i < 12; i++) {
      final s = defaultStd[i] == 0 ? 1.0 : defaultStd[i];
      tensor[i] = (raw[i] - defaultMean[i]) / s;
    }
    return tensor;
  }
}

/// Model C: Posture Camera Image [1, 224, 224, 3] (float32 0.0-255.0) -> Output [1, 1]
class PostureModelInput {
  static const int width = 224;
  static const int height = 224;
  static const int channels = 3;

  /// 1 * 224 * 224 * 3 = 150,528 elemanlı float32 (0.0 - 255.0) tensör üretir
  static Float32List createFloat32ImageTensor(List<int>? rgbBytes) {
    const totalElements = 1 * width * height * channels;
    final tensor = Float32List(totalElements);

    if (rgbBytes != null && rgbBytes.length == totalElements) {
      for (int i = 0; i < totalElements; i++) {
        tensor[i] = rgbBytes[i].clamp(0, 255).toDouble();
      }
    } else {
      // Kamera bağlı değilken test amaçlı sentetik 224x224 RGB float32 frame
      for (int i = 0; i < totalElements; i++) {
        tensor[i] = (i % 255).toDouble();
      }
    }
    return tensor;
  }
}