import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_litert/flutter_litert.dart';

import 'ai_input_models.dart';

/// Loads the 3 TFLite models from assets and runs real on-device inference.
class HealthAiService {
  static const _ecgPath = 'assets/models/ecg_heartbeat.tflite';
  static const _cardioPath = 'assets/models/cardiovascular.tflite';
  static const _posturePath = 'assets/models/posture_keypoints.tflite';
  static const _scalerPath = 'assets/models/cardiovascular_scaler.json';

  Interpreter? _ecg;
  Interpreter? _cardio;
  Interpreter? _posture;
  List<double> _mean = <double>[];
  List<double> _scale = <double>[];

  bool get isReady => _ecg != null && _cardio != null && _posture != null;

  Future<void> load() async {
    if (isReady) return;
    _ecg = await Interpreter.fromAsset(_ecgPath);
    _cardio = await Interpreter.fromAsset(_cardioPath);
    _posture = await Interpreter.fromAsset(_posturePath);

    final scaler =
        jsonDecode(await rootBundle.loadString(_scalerPath)) as Map<String, dynamic>;
    _mean = (scaler['mean'] as List).map((e) => (e as num).toDouble()).toList();
    _scale = (scaler['scale'] as List).map((e) => (e as num).toDouble()).toList();
  }

  /// ECG: input [1,187,1] -> 5 class probabilities [N, S, V, F, Q].
  List<double> runEcg(List<double> samples187) {
    final input = <List<List<double>>>[
      List<List<double>>.generate(187, (i) => <double>[samples187[i]]),
    ];
    final output = <List<double>>[List<double>.filled(5, 0.0)];
    _ecg!.run(input, output);
    return List<double>.from(output[0]);
  }

  /// Cardiovascular: 12 standardized features -> risk 0..1.
  double runCardio(CardioModelInput data) {
    final raw = List<double>.from(data.rawFeatures);
    // App uses gender 0=female/1=male; the training data used 1=female/2=male.
    raw[1] = raw[1] + 1.0;
    final x = List<double>.generate(12, (i) => (raw[i] - _mean[i]) / _scale[i]);
    final input = <List<double>>[x];
    final output = <List<double>>[List<double>.filled(1, 0.0)];
    _cardio!.run(input, output);
    return output[0][0].clamp(0.0, 1.0).toDouble();
  }

  /// Posture: flat RGB float32 tensor (224*224*3, values 0..255) -> risk 0..1.
  double runPosture(List<double> flatRgb) {
    final input = <List<List<List<double>>>>[
      List<List<List<double>>>.generate(224, (y) {
        return List<List<double>>.generate(224, (x) {
          final o = (y * 224 + x) * 3;
          return <double>[flatRgb[o], flatRgb[o + 1], flatRgb[o + 2]];
        });
      }),
    ];
    final output = <List<double>>[List<double>.filled(1, 0.0)];
    _posture!.run(input, output);
    return output[0][0].clamp(0.0, 1.0).toDouble();
  }

  /// Decodes a JPEG/PNG photo, resizes it to 224x224 and returns the flat
  /// RGB float tensor (150,528 values, 0..255) the posture model expects.
  static Future<List<double>> imageBytesToTensor(Uint8List bytes) async {
    final codec =
        await ui.instantiateImageCodec(bytes, targetWidth: 224, targetHeight: 224);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rgba = data!.buffer.asUint8List();
    final out = List<double>.filled(224 * 224 * 3, 0.0);
    for (int i = 0; i < 224 * 224; i++) {
      out[i * 3] = rgba[i * 4].toDouble();
      out[i * 3 + 1] = rgba[i * 4 + 1].toDouble();
      out[i * 3 + 2] = rgba[i * 4 + 2].toDouble();
    }
    frame.image.dispose();
    codec.dispose();
    return out;
  }

  void dispose() {
    _ecg?.close();
    _cardio?.close();
    _posture?.close();
    _ecg = _cardio = _posture = null;
  }
}
