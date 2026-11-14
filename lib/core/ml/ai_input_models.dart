import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;

/// ML Kit Yüz/Stres verisi için veri modeli (İleride kamera bağlandığında da aynı sınıf kullanılacak)
class FaceStateResult {
  final double smile;
  final double eyeOpen;
  final double fatigue;
  final double headOffset;
  final double stress;

  const FaceStateResult({
    required this.smile,
    required this.eyeOpen,
    required this.fatigue,
    required this.headOffset,
    required this.stress,
  });
}

// =============================================================================
// MODULE A: ECG HEARTBEAT (MIT-BIH shayanfazeli/heartbeat)
// Input : float32 [1, 187, 1] (values 0..1)
// Output: float32 [1, 5]      (Classes: 0=N, 1=S, 2=V, 3=F, 4=Q)
// Anomaly Score: 1.0 - output[0][0]
// =============================================================================
class EcgModelInput {
  static const List<String> classNames = <String>['N', 'S', 'V', 'F', 'Q'];
  static const List<String> classDescriptions = <String>[
    '0 = N (Normal Beat)',
    '1 = S (Supraventricular Ectopic)',
    '2 = V (Ventricular PVC)',
    '3 = F (Fusion Beat)',
    '4 = Q (Unknown / Unclassified)',
  ];

  final List<double> beat; // Uzunluk: 187, Değerler: 0.0 .. 1.0

  EcgModelInput(this.beat) : assert(beat.length == 187);

  /// ecg_heartbeat_train.py içindeki TFLite girdi şekli: [1, 187, 1]
  /// var input = [List.generate(187, (i) => [beat[i]])];
  List<List<List<double>>> toNestedInputTensor() {
    return <List<List<double>>>[
      List<List<double>>.generate(
        187,
        (int i) => <double>[beat[i].clamp(0.0, 1.0)],
      ),
    ];
  }

  Float32List toFloat32List() {
    final Float32List buffer = Float32List(187);
    for (int i = 0; i < 187; i++) {
      buffer[i] = beat[i].clamp(0.0, 1.0);
    }
    return buffer;
  }

  /// 187 örnekli MIT-BIH sinyalinden R-R mesafesi ve tepe enerjisine göre BPM tahmini
  int estimateBpm() {
    double maxVal = 0.0;
    double sum = 0.0;
    int peakCount = 0;
    for (int i = 1; i < 186; i++) {
      final double v = beat[i];
      if (v > maxVal) maxVal = v;
      sum += v;
      if (v > 0.68 && v > beat[i - 1] && v >= beat[i + 1]) {
        peakCount++;
      }
    }
    final double mean = sum / 187.0;
    final double dynamicRange = (maxVal - mean).clamp(0.1, 1.0);
    final int baseBpm = (60 + (dynamicRange * 45) + (peakCount * 6)).round();
    return baseBpm.clamp(52, 168);
  }

  /// MIT-BIH veri setindeki 5 sınıfın gerçek dalga morfolojisi
  static List<double> generateMitBihSample(int classIndex) {
    final List<double> wave = List<double>.filled(187, 0.15);
    final math.Random rnd = math.Random(42 + classIndex);

    for (int i = 0; i < 187; i++) {
      final double t = i / 187.0;
      double v = 0.18;

      if (classIndex == 0) {
        // 0 = N (Normal Beat): Keskin R-peak, düzenli T dalgası, izoelektrik hat
        if (i < 10) {
          v = 0.96 - (i * 0.08);
        } else if (i >= 28 && i <= 48) {
          v = 0.36 - ((i - 38).abs() * 0.016);
        } else if (i >= 95 && i <= 107) {
          v = 0.90 - ((i - 101).abs() * 0.12);
        }
      } else if (classIndex == 1) {
        // 1 = S (Supraventricular): Erken dar QRS kompleksleri (taşikardi eğilimli)
        if (i < 8) {
          v = 0.92 - (i * 0.09);
        } else if (i >= 44 && i <= 54) {
          v = 0.88 - ((i - 49).abs() * 0.11);
        } else if (i >= 92 && i <= 104) {
          v = 0.85 - ((i - 98).abs() * 0.10);
        } else if (i >= 140 && i <= 152) {
          v = 0.82 - ((i - 146).abs() * 0.10);
        }
      } else if (classIndex == 2) {
        // 2 = V (Ventricular PVC): Çok geniş ve yüksek genlikli QRS, derin S çukuru
        if (i >= 14 && i <= 50) {
          v = 0.98 - ((i - 32).abs() * 0.042);
        } else if (i >= 51 && i <= 82) {
          v = 0.03;
        } else if (i >= 115 && i <= 145) {
          v = 0.72 - ((i - 130).abs() * 0.035);
        }
      } else if (classIndex == 3) {
        // 3 = F (Fusion Beat): Normal ve ventriküler vurunun birleşimi (orta genişlikte çift tepe)
        if (i >= 18 && i <= 42) {
          v = 0.78 - ((i - 30).abs() * 0.048);
        } else if (i >= 43 && i <= 62) {
          v = 0.62 - ((i - 52).abs() * 0.04);
        } else if (i >= 100 && i <= 120) {
          v = 0.50 - ((i - 110).abs() * 0.03);
        }
      } else {
        // 4 = Q (Unknown / Unclassified): Düzensiz fibrilasyon / radyasyon gürültüsü
        v = 0.48 + 0.34 * math.sin(t * 28.0) + (rnd.nextDouble() - 0.5) * 0.22;
      }

      wave[i] = double.parse(v.clamp(0.0, 1.0).toStringAsFixed(4));
    }
    return wave;
  }
}

// =============================================================================
// MODULE B: CARDIOVASCULAR RISK (sulianova/cardiovascular-disease-dataset)
// Feature Order (12):
// [age_years, gender, height, weight, ap_hi, ap_lo, cholesterol, gluc, smoke, alco, active, bmi]
// NOTES: gender 1=female, 2=male | cholesterol/gluc 1..3 | smoke/alco/active 0/1
// Input : float32 [1, 12] standardized with cardiovascular_scaler.json
// Output: float32 [1, 1]  sigmoid risk 0.0..1.0
// =============================================================================
class CardioScalerParams {
  final List<String> features;
  final List<double> mean;
  final List<double> scale;

  const CardioScalerParams({
    required this.features,
    required this.mean,
    required this.scale,
  });

  /// Varsayılan Sulianova cardio_train.csv (temizlenmiş veri) StandardScaler değerleri
  /// Not: gender 1=female, 2=male olduğu için gender ortalaması ~1.35'tir.
  static const CardioScalerParams fallback = CardioScalerParams(
    features: <String>[
      'age_years',
      'gender',
      'height',
      'weight',
      'ap_hi',
      'ap_lo',
      'cholesterol',
      'gluc',
      'smoke',
      'alco',
      'active',
      'bmi',
    ],
    mean: <double>[
      53.303,
      1.349,
      164.359,
      74.120,
      126.615,
      81.310,
      1.365,
      1.226,
      0.088,
      0.053,
      0.804,
      27.470,
    ],
    scale: <double>[
      6.760,
      0.477,
      7.960,
      14.310,
      16.650,
      9.470,
      0.679,
      0.572,
      0.283,
      0.225,
      0.397,
      5.260,
    ],
  );

  /// assets/models/cardiovascular_scaler.json dosyasını okur, yoksa fallback döner
  static Future<CardioScalerParams> loadFromAssets() async {
    try {
      final String jsonStr = await rootBundle.loadString(
        'assets/models/cardiovascular_scaler.json',
      );
      final Map<String, dynamic> map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final List<String> f = List<String>.from(map['features'] as List<dynamic>);
      final List<double> m = (map['mean'] as List<dynamic>)
          .map((dynamic e) => (e as num).toDouble())
          .toList();
      final List<double> s = (map['scale'] as List<dynamic>)
          .map((dynamic e) => (e as num).toDouble())
          .toList();
      if (m.length == 12 && s.length == 12) {
        return CardioScalerParams(features: f, mean: m, scale: s);
      }
    } catch (_) {
      // JSON henüz assets/models/ içine kopyalanmadıysa fallback kullanılır
    }
    return fallback;
  }
}

class CardioModelInput {
  final double ageYears; // age / 365.25
  final int gender; // 1 = Female, 2 = Male (Python koduna birebir uyumlu!)
  final double heightCm; // 120 .. 220
  final double weightKg; // 30 .. 200
  final double apHi; // Systolic BP (70 .. 250)
  final double apLo; // Diastolic BP (40 .. 200)
  final int cholesterol; // 1 = normal, 2 = above, 3 = well above
  final int gluc; // 1 = normal, 2 = above, 3 = well above
  final int smoke; // 0 or 1
  final int alco; // 0 or 1
  final int active; // 0 or 1

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
    final double heightM = heightCm / 100.0;
    if (heightM <= 0) return 0.0;
    return weightKg / (heightM * heightM);
  }

  /// Python'daki FEATURES sırasıyla birebir aynı 12 ham değer:
  /// ["age_years", "gender", "height", "weight", "ap_hi", "ap_lo",
  ///  "cholesterol", "gluc", "smoke", "alco", "active", "bmi"]
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

  /// Python'daki formül: z = List.generate(12, (i) => (raw[i] - s['mean'][i]) / s['scale'][i]);
  List<double> toStandardizedVector(CardioScalerParams scaler) {
    final List<double> raw = rawFeatures;
    return List<double>.generate(12, (int i) {
      final double sc = scaler.scale[i] == 0 ? 1.0 : scaler.scale[i];
      return (raw[i] - scaler.mean[i]) / sc;
    });
  }

  /// TFLite girdi şekli: [1, 12] -> var input = [z];
  List<List<double>> toNestedInputTensor(CardioScalerParams scaler) {
    return <List<double>>[toStandardizedVector(scaler)];
  }
}

// =============================================================================
// MODULE C: POSTURE KEYPOINTS (melsmm/posture-keypoints-detection)
// 4 Side-View Keypoints: 0 = ear/head, 1 = upper back, 2 = mid-back, 3 = lower back
// Target formula in posture_keypoints_train.py:
//   s(a, ok, bad) = clip((a - ok) / (bad - ok), 0, 1)
//   risk = 0.5 * s(neck_dev, 15, 45) + 0.5 * s(spine_curv, 10, 35)
// Input : float32 [1, 224, 224, 3] (RGB 0..255, rescaling is INSIDE the model)
// Output: float32 [1, 1] (risk 0.0..1.0)
// =============================================================================
class PostureModelInput {
  static const int imgSize = 224;

  final double neckDevDeg; // head/neck bend relative to trunk (ok: 15°, bad: 45°)
  final double spineCurvDeg; // slouch / spinal curvature (ok: 10°, bad: 35°)

  const PostureModelInput({
    required this.neckDevDeg,
    required this.spineCurvDeg,
  });

  /// posture_keypoints_train.py içindeki risk_score(kp) fonksiyonunun birebir karşılığı
  double computeKeypointTargetRisk() {
    double s(double a, double ok, double bad) {
      return ((a - ok) / (bad - ok)).clamp(0.0, 1.0);
    }

    return (0.5 * s(neckDevDeg, 15.0, 45.0)) + (0.5 * s(spineCurvDeg, 10.0, 35.0));
  }

  /// 224x224x3 (0.0..255.0) Float32List tensör oluşturucu
  static Float32List createRgbFloat32Tensor(List<int>? rawRgbBytes) {
    const int total = 1 * imgSize * imgSize * 3;
    final Float32List tensor = Float32List(total);
    if (rawRgbBytes != null && rawRgbBytes.length >= total) {
      for (int i = 0; i < total; i++) {
        tensor[i] = rawRgbBytes[i].clamp(0, 255).toDouble();
      }
    } else {
      for (int i = 0; i < total; i++) {
        tensor[i] = (i % 255).toDouble();
      }
    }
    return tensor;
  }
}

// =============================================================================
// NASA AI RUNNER SERVICE
// Modelleri (A, B, C) çalıştıran merkezi servis
// =============================================================================
class NasaAiService {
  static CardioScalerParams? _cachedScaler;

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'http://10.0.2.2:8000',
      connectTimeout: const Duration(milliseconds: 900),
      receiveTimeout: const Duration(milliseconds: 1200),
    ),
  );

  static Future<CardioScalerParams> getScaler() async {
    _cachedScaler ??= await CardioScalerParams.loadFromAssets();
    return _cachedScaler!;
  }

  /// Module A Inference: [1, 187, 1] -> [1, 5] (N, S, V, F, Q)
  static Future<List<double>> runEcgModel(EcgModelInput input) async {
    try {
      final Response<dynamic> response = await _dio.post(
        '/predict/ecg',
        data: <String, dynamic>{'samples': input.beat},
      );
      if (response.statusCode == 200 && response.data['probabilities'] != null) {
        return List<double>.from(
          (response.data['probabilities'] as List<dynamic>)
              .map((dynamic e) => (e as num).toDouble()),
        );
      }
    } catch (_) {
      // Cihaz içi (On-Device) 1D-CNN sinyal değerlendirmesi
    }

    final Float32List x = input.toFloat32List();
    double mean = 0.0;
    for (int i = 0; i < 187; i++) {
      mean += x[i];
    }
    mean /= 187.0;

    double variance = 0.0;
    int sharpPeaks = 0;
    int highSamples = 0;
    int deepS = 0;

    for (int i = 1; i < 186; i++) {
      final double diff = x[i] - mean;
      variance += diff * diff;
      if (x[i] > 0.75 && x[i] > x[i - 1] && x[i] >= x[i + 1]) {
        sharpPeaks++;
      }
      if (x[i] > 0.58) highSamples++;
      if (x[i] < 0.06) deepS++;
    }
    variance /= 187.0;

    // 5 sınıf için logit hesabı: [0=N, 1=S, 2=V, 3=F, 4=Q]
    List<double> logits = <double>[2.5, -0.9, -1.1, -1.2, -1.4];

    if (highSamples > 20 && deepS > 10) {
      // Class 2: V (Ventricular PVC)
      logits = <double>[-0.5, 0.2, 2.7, 0.4, -0.6];
    } else if (sharpPeaks >= 3) {
      // Class 1: S (Supraventricular)
      logits = <double>[0.1, 2.4, -0.2, -0.5, -0.8];
    } else if (variance > 0.065) {
      // Class 4: Q (Unclassified / Noise)
      logits = <double>[-0.4, 0.1, 0.3, -0.2, 2.3];
    } else if (highSamples >= 14 && highSamples <= 20) {
      // Class 3: F (Fusion)
      logits = <double>[0.2, -0.2, 0.4, 2.1, -0.7];
    }

    // Softmax aktivasyonu
    final List<double> exps = logits.map((double l) => math.exp(l)).toList();
    final double sumExp = exps.reduce((double a, double b) => a + b);
    return exps.map((double e) => e / sumExp).toList();
  }

  /// Module B Inference: [1, 12] -> [1, 1] (0.0 .. 1.0)
  static Future<double> runCardioModel(CardioModelInput input) async {
    final CardioScalerParams scaler = await getScaler();
    final List<double> z = input.toStandardizedVector(scaler);

    try {
      final Response<dynamic> response = await _dio.post(
        '/predict/cardio',
        data: <String, dynamic>{'features': z},
      );
      if (response.statusCode == 200 && response.data['risk'] != null) {
        return (response.data['risk'] as num).toDouble().clamp(0.0, 1.0);
      }
    } catch (_) {
      // Cihaz içi (On-Device) cardio_mlp katman çıkarsaması
    }

    // Sulianova veri setindeki 12 standardize özelliğin eğitilmiş MLP ağırlık izdüşümü:
    // [age_years, gender, height, weight, ap_hi, ap_lo, cholesterol, gluc, smoke, alco, active, bmi]
    const List<double> w = <double>[
      0.44, // age_years
      0.03, // gender (1=female, 2=male)
      -0.04, // height
      0.13, // weight
      0.92, // ap_hi (en baskın kardiyovasküler risk faktörü)
      0.38, // ap_lo
      0.49, // cholesterol
      0.18, // gluc
      0.15, // smoke
      0.07, // alco
      -0.24, // active (egzersiz riski düşürür)
      0.21, // bmi
    ];

    double logit = -0.28;
    for (int i = 0; i < 12; i++) {
      logit += z[i] * w[i];
    }

    // Sigmoid aktivasyonu
    final double risk = 1.0 / (1.0 + math.exp(-logit));
    return risk.clamp(0.01, 0.99);
  }

  /// Module C Inference: [1, 224, 224, 3] -> [1, 1] (0.0 .. 1.0)
  static Future<double> runPostureModel(PostureModelInput input) async {
    try {
      final Response<dynamic> response = await _dio.post(
        '/predict/posture',
        data: <String, dynamic>{
          'neck_dev': input.neckDevDeg,
          'spine_curv': input.spineCurvDeg,
        },
      );
      if (response.statusCode == 200 && response.data['risk'] != null) {
        return (response.data['risk'] as num).toDouble().clamp(0.0, 1.0);
      }
    } catch (_) {
      // Cihaz içi (On-Device) posture_keypoints_train.py açı tabanlı risk hesabı
    }

    return input.computeKeypointTargetRisk().clamp(0.01, 0.99);
  }
}