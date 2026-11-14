import 'package:flutter/material.dart';
import 'package:nasa_health_app/core/ml/ai_input_models.dart';
import 'package:nasa_health_app/core/theme/app_theme.dart';

class AiEvaluationBundle {
  final double ecgAnomalyRisk; // 1.0 - output[0]
  final int heartRateBpm;
  final String dominantEcgClass; // N, S, V, F, Q
  final double cardioRisk; // output[0][0]
  final int systolic; // ap_hi
  final int diastolic; // ap_lo
  final double bmi;
  final double postureRisk; // output[0][0]
  final double neckDevDeg;
  final double spineCurvDeg;

  const AiEvaluationBundle({
    required this.ecgAnomalyRisk,
    required this.heartRateBpm,
    required this.dominantEcgClass,
    required this.cardioRisk,
    required this.systolic,
    required this.diastolic,
    required this.bmi,
    required this.postureRisk,
    required this.neckDevDeg,
    required this.spineCurvDeg,
  });
}

class AiDiagnosticsScreen extends StatefulWidget {
  final int initialTabIndex;
  final ValueChanged<AiEvaluationBundle>? onModelsEvaluated;

  const AiDiagnosticsScreen({
    super.key,
    this.initialTabIndex = 0,
    this.onModelsEvaluated,
  });

  @override
  State<AiDiagnosticsScreen> createState() => AiDiagnosticsScreenState();
}

class AiDiagnosticsScreenState extends State<AiDiagnosticsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // --- MODULE A (ecg_heartbeat.tflite) STATE ---
  int _selectedEcgClassIndex = 0;
  late List<double> _ecgSamples;
  final TextEditingController _ecgRawController = TextEditingController();
  List<double> _ecgProbs = <double>[0.91, 0.03, 0.03, 0.02, 0.01];
  int _computedBpm = 72;

  // --- MODULE B (cardiovascular.tflite) STATE ---
  // Feature order: [age_years, gender, height, weight, ap_hi, ap_lo, cholesterol, gluc, smoke, alco, active, bmi]
  double _ageYears = 38.0;
  int _gender = 2; // 1 = Female, 2 = Male (cardiovascular_train.py standardı!)
  double _heightCm = 176.0;
  double _weightKg = 75.0;
  double _apHi = 120.0;
  double _apLo = 80.0;
  int _cholesterol = 1; // 1=normal, 2=above, 3=well above
  int _gluc = 1; // 1=normal, 2=above, 3=well above
  bool _smoke = false;
  bool _alco = false;
  bool _active = true;
  double _cardioRisk = 0.17;
  List<double> _standardizedZ = List<double>.filled(12, 0.0);

  // --- MODULE C (posture_keypoints.tflite) STATE ---
  // Keypoints: 0=ear/head, 1=upper back, 2=mid-back, 3=lower back
  String _selectedPosturePreset = 'Nominal Microgravity Neutral Posture';
  double _neckDevDeg = 18.0; // ok=15, bad=45
  double _spineCurvDeg = 12.0; // ok=10, bad=35
  double _postureRisk = 0.09;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    _initializeModels();
  }

  Future<void> _initializeModels() async {
    await _loadMitBihClassSample(0, notify: false);
    await _evaluateModuleB(showToast: false);
    await _evaluateModuleC(showToast: false);
  }

  void switchToTab(int index) {
    if (mounted) {
      _tabController.animateTo(index.clamp(0, 2));
    }
  }

  Future<void> _loadMitBihClassSample(int classIdx, {bool notify = true}) async {
    final List<double> beat = EcgModelInput.generateMitBihSample(classIdx);
    final EcgModelInput input = EcgModelInput(beat);
    final List<double> probs = await NasaAiService.runEcgModel(input);

    if (!mounted) return;
    setState(() {
      _selectedEcgClassIndex = classIdx;
      _ecgSamples = beat;
      _ecgRawController.text = beat.join(', ');
      _ecgProbs = probs;
      _computedBpm = input.estimateBpm();
    });
    if (notify) _emitEvaluation();
  }

  Future<void> _evaluateModuleA() async {
    final List<double> parsed = _ecgRawController.text
        .split(',')
        .map((String s) => double.tryParse(s.trim()) ?? 0.0)
        .toList();

    final List<double> beat187 = List<double>.generate(
      187,
      (int i) => i < parsed.length ? parsed[i].clamp(0.0, 1.0) : 0.0,
    );

    final EcgModelInput input = EcgModelInput(beat187);
    final List<double> probs = await NasaAiService.runEcgModel(input);

    if (!mounted) return;
    setState(() {
      _ecgSamples = beat187;
      _ecgProbs = probs;
      _computedBpm = input.estimateBpm();
    });

    _emitEvaluation();
    final double anomalyScore = 1.0 - probs[0];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: NasaColors.deepSpaceBlue,
        content: Text(
          'Module A (ecg_heartbeat.tflite): Anomaly Score (1 - P[N]) = ${(anomalyScore * 100).toStringAsFixed(1)}%',
        ),
      ),
    );
  }

  Future<void> _evaluateModuleB({bool showToast = true}) async {
    final CardioModelInput input = CardioModelInput(
      ageYears: _ageYears,
      gender: _gender,
      heightCm: _heightCm,
      weightKg: _weightKg,
      apHi: _apHi,
      apLo: _apLo,
      cholesterol: _cholesterol,
      gluc: _gluc,
      smoke: _smoke ? 1 : 0,
      alco: _alco ? 1 : 0,
      active: _active ? 1 : 0,
    );

    final CardioScalerParams scaler = await NasaAiService.getScaler();
    final List<double> z = input.toStandardizedVector(scaler);
    final double risk = await NasaAiService.runCardioModel(input);

    if (!mounted) return;
    setState(() {
      _standardizedZ = z;
      _cardioRisk = risk;
    });

    _emitEvaluation();
    if (showToast) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NasaColors.deepSpaceBlue,
          content: Text(
            'Module B (cardiovascular.tflite): Risk = ${(risk * 100).toStringAsFixed(1)}% | BMI = ${input.bmi.toStringAsFixed(1)}',
          ),
        ),
      );
    }
  }

  Future<void> _evaluateModuleC({bool showToast = true}) async {
    final PostureModelInput input = PostureModelInput(
      neckDevDeg: _neckDevDeg,
      spineCurvDeg: _spineCurvDeg,
    );
    final double risk = await NasaAiService.runPostureModel(input);

    if (!mounted) return;
    setState(() {
      _postureRisk = risk;
    });

    _emitEvaluation();
    if (showToast) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NasaColors.deepSpaceBlue,
          content: Text(
            'Module C (posture_keypoints.tflite): Ergonomic Risk = ${(risk * 100).toStringAsFixed(1)}%',
          ),
        ),
      );
    }
  }

  void _emitEvaluation() {
    int maxIdx = 0;
    for (int i = 1; i < _ecgProbs.length; i++) {
      if (_ecgProbs[i] > _ecgProbs[maxIdx]) maxIdx = i;
    }

    final double anomalyScore = (1.0 - _ecgProbs[0]).clamp(0.0, 1.0);
    final double heightM = _heightCm / 100.0;
    final double bmi = _weightKg / (heightM * heightM);

    widget.onModelsEvaluated?.call(
      AiEvaluationBundle(
        ecgAnomalyRisk: anomalyScore,
        heartRateBpm: _computedBpm,
        dominantEcgClass: EcgModelInput.classDescriptions[maxIdx],
        cardioRisk: _cardioRisk,
        systolic: _apHi.round(),
        diastolic: _apLo.round(),
        bmi: bmi,
        postureRisk: _postureRisk,
        neckDevDeg: _neckDevDeg,
        spineCurvDeg: _spineCurvDeg,
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ecgRawController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: NasaColors.stationGrey,
          child: TabBar(
            controller: _tabController,
            indicatorColor: NasaColors.biometricCyan,
            labelColor: NasaColors.biometricCyan,
            unselectedLabelColor: NasaColors.nebulaGrey,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            tabs: const [
              Tab(text: 'MODULE A: ECG\n[1, 187, 1]'),
              Tab(text: 'MODULE B: CARDIO\n[1, 12]'),
              Tab(text: 'MODULE C: POSTURE\n[1, 224, 224, 3]'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildModuleATab(),
              _buildModuleBTab(),
              _buildModuleCTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 1: MODULE A - ECG Heartbeat (MIT-BIH) 1D-CNN -> ecg_heartbeat.tflite
  // ===========================================================================
  Widget _buildModuleATab() {
    final double anomalyProb = (1.0 - _ecgProbs[0]).clamp(0.0, 1.0);
    final Color anomalyColor = anomalyProb > 0.35
        ? NasaColors.orbitRed
        : NasaColors.capsuleGreen;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSpecBanner(
            title: 'MODULE A: ecg_heartbeat.tflite (MIT-BIH 1D-CNN)',
            inputSpec: 'float32 [1, 187, 1] (min-max scaled 0..1, no scaler needed)',
            outputSpec: 'float32 [1, 5] Softmax (N, S, V, F, Q) | Anomaly = 1 - output[0]',
          ),
          const SizedBox(height: 12),

          // Heart-region Anomaly Score Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: NasaColors.stationGrey,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: anomalyColor, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'HEART-REGION ANOMALY SCORE (1 - P[Normal])',
                      style: TextStyle(color: NasaColors.nebulaGrey, fontSize: 10),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(anomalyProb * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: anomalyColor,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'ESTIMATED HR',
                      style: TextStyle(color: NasaColors.nebulaGrey, fontSize: 10),
                    ),
                    Text(
                      '$_computedBpm bpm',
                      style: const TextStyle(
                        color: NasaColors.biometricCyan,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 187 Örnekli Canlı EKG Grafiği
          Container(
            height: 135,
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NasaColors.stationGrey,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: NasaColors.biometricCyan.withValues(alpha: 0.4)),
            ),
            child: CustomPaint(painter: _EcgWavePainter(_ecgSamples)),
          ),
          const SizedBox(height: 14),

          const Text(
            'LOAD MIT-BIH TEST BEAT (mitbih_test.csv CLASSES 0..4):',
            style: TextStyle(color: NasaColors.nebulaGrey, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List<Widget>.generate(5, (int idx) {
              final bool selected = _selectedEcgClassIndex == idx;
              return ChoiceChip(
                label: Text(
                  EcgModelInput.classDescriptions[idx],
                  style: const TextStyle(fontSize: 11),
                ),
                selected: selected,
                selectedColor: NasaColors.deepSpaceBlue,
                backgroundColor: NasaColors.stationGrey,
                onSelected: (_) => _loadMitBihClassSample(idx),
              );
            }),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _ecgRawController,
            maxLines: 3,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText: '187 Float32 Samples (0.0 .. 1.0, comma-separated)',
              labelStyle: const TextStyle(color: NasaColors.biometricCyan, fontSize: 12),
              filled: true,
              fillColor: NasaColors.stationGrey,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: NasaColors.biometricCyan,
                foregroundColor: NasaColors.darkMatter,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _evaluateModuleA,
              icon: const Icon(Icons.monitor_heart_rounded),
              label: const Text(
                'RUN ecg_heartbeat.tflite ([1, 187, 1])',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 18),

          const Text(
            'RHYTHM PROBABILITIES — OUTPUT [1, 5]:',
            style: TextStyle(color: NasaColors.pureWhite, fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 10),
          ...List<Widget>.generate(5, (int index) {
            final double prob = _ecgProbs[index];
            final Color barColor = index == 0 ? NasaColors.capsuleGreen : NasaColors.orbitRed;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          EcgModelInput.classDescriptions[index],
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        '${(prob * 100).toStringAsFixed(1)}%',
                        style: TextStyle(color: barColor, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: prob,
                    minHeight: 7,
                    backgroundColor: NasaColors.stationGrey,
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 2: MODULE B - Cardiovascular Risk (cardio_train.csv) -> cardiovascular.tflite
  // ===========================================================================
  Widget _buildModuleBTab() {
    final CardioModelInput currentInput = CardioModelInput(
      ageYears: _ageYears,
      gender: _gender,
      heightCm: _heightCm,
      weightKg: _weightKg,
      apHi: _apHi,
      apLo: _apLo,
      cholesterol: _cholesterol,
      gluc: _gluc,
      smoke: _smoke ? 1 : 0,
      alco: _alco ? 1 : 0,
      active: _active ? 1 : 0,
    );

    final Color riskColor = _cardioRisk > 0.50
        ? NasaColors.orbitRed
        : (_cardioRisk > 0.30 ? NasaColors.warningAmber : NasaColors.capsuleGreen);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSpecBanner(
            title: 'MODULE B: cardiovascular.tflite + cardiovascular_scaler.json',
            inputSpec: 'float32 [1, 12] -> z = (raw - mean) / scale | gender: 1=F, 2=M',
            outputSpec: 'float32 [1, 1] Sigmoid Risk Probability (0.0..1.0)',
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: NasaColors.stationGrey,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: riskColor, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CARDIOVASCULAR RISK [1, 1]',
                      style: TextStyle(color: NasaColors.nebulaGrey, fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(_cardioRisk * 100).toStringAsFixed(1)}%',
                      style: TextStyle(color: riskColor, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'COMPUTED BMI (FEATURE #12)',
                      style: TextStyle(color: NasaColors.nebulaGrey, fontSize: 10),
                    ),
                    Text(
                      '${currentInput.bmi.toStringAsFixed(2)} kg/m²',
                      style: const TextStyle(
                        color: NasaColors.biometricCyan,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          _buildSliderRow(
            label: '1. age_years (age_days / 365.25)',
            value: _ageYears,
            min: 22,
            max: 68,
            unit: 'yrs',
            onChanged: (double v) {
              setState(() => _ageYears = v.roundToDouble());
              _evaluateModuleB(showToast: false);
            },
          ),

          // Dikkat: cardiovascular_train.py satır 47: gender 1=female, 2=male
          Row(
            children: [
              const Expanded(
                child: Text(
                  '2. gender (1=Female, 2=Male):',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              ChoiceChip(
                label: const Text('1: Female'),
                selected: _gender == 1,
                selectedColor: NasaColors.deepSpaceBlue,
                onSelected: (_) {
                  setState(() => _gender = 1);
                  _evaluateModuleB(showToast: false);
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('2: Male'),
                selected: _gender == 2,
                selectedColor: NasaColors.deepSpaceBlue,
                onSelected: (_) {
                  setState(() => _gender = 2);
                  _evaluateModuleB(showToast: false);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          _buildSliderRow(
            label: '3. height (120..220 cm)',
            value: _heightCm,
            min: 140,
            max: 210,
            unit: 'cm',
            onChanged: (double v) {
              setState(() => _heightCm = v.roundToDouble());
              _evaluateModuleB(showToast: false);
            },
          ),
          _buildSliderRow(
            label: '4. weight (30..200 kg)',
            value: _weightKg,
            min: 45,
            max: 135,
            unit: 'kg',
            onChanged: (double v) {
              setState(() => _weightKg = v.roundToDouble());
              _evaluateModuleB(showToast: false);
            },
          ),
          _buildSliderRow(
            label: '5. ap_hi (Systolic BP 70..250)',
            value: _apHi,
            min: 85,
            max: 200,
            unit: 'mmHg',
            onChanged: (double v) {
              setState(() {
                _apHi = v.roundToDouble();
                if (_apHi <= _apLo) _apLo = (_apHi - 15).clamp(40, 190);
              });
              _evaluateModuleB(showToast: false);
            },
          ),
          _buildSliderRow(
            label: '6. ap_lo (Diastolic BP 40..200)',
            value: _apLo,
            min: 50,
            max: 130,
            unit: 'mmHg',
            onChanged: (double v) {
              setState(() {
                _apLo = v.roundToDouble();
                if (_apLo >= _apHi) _apHi = (_apLo + 15).clamp(70, 250);
              });
              _evaluateModuleB(showToast: false);
            },
          ),
          const SizedBox(height: 8),

          _buildTierSelector(
            label: '7. cholesterol (1=normal, 2=above, 3=well above)',
            currentValue: _cholesterol,
            onChanged: (int v) {
              setState(() => _cholesterol = v);
              _evaluateModuleB(showToast: false);
            },
          ),
          const SizedBox(height: 10),
          _buildTierSelector(
            label: '8. gluc (1=normal, 2=above, 3=well above)',
            currentValue: _gluc,
            onChanged: (int v) {
              setState(() => _gluc = v);
              _evaluateModuleB(showToast: false);
            },
          ),
          const SizedBox(height: 10),

          Card(
            margin: EdgeInsets.zero,
            color: NasaColors.stationGrey,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('9. smoke (0 or 1)', style: TextStyle(fontSize: 13)),
                  value: _smoke,
                  activeThumbColor: NasaColors.orbitRed,
                  onChanged: (bool v) {
                    setState(() => _smoke = v);
                    _evaluateModuleB(showToast: false);
                  },
                ),
                SwitchListTile(
                  title: const Text('10. alco (0 or 1)', style: TextStyle(fontSize: 13)),
                  value: _alco,
                  activeThumbColor: NasaColors.warningAmber,
                  onChanged: (bool v) {
                    setState(() => _alco = v);
                    _evaluateModuleB(showToast: false);
                  },
                ),
                SwitchListTile(
                  title: const Text('11. active (0 or 1)', style: TextStyle(fontSize: 13)),
                  value: _active,
                  activeThumbColor: NasaColors.capsuleGreen,
                  onChanged: (bool v) {
                    setState(() => _active = v);
                    _evaluateModuleB(showToast: false);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // StandardScaler z vektörü önizlemesi
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: NasaColors.stationGrey,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Standardized z [1,12]: [${_standardizedZ.map((double e) => e.toStringAsFixed(2)).join(", ")}]',
              style: const TextStyle(
                color: NasaColors.nebulaGrey,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: NasaColors.biometricCyan,
                foregroundColor: NasaColors.darkMatter,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => _evaluateModuleB(showToast: true),
              icon: const Icon(Icons.calculate_rounded),
              label: const Text(
                'RUN cardiovascular.tflite ([1, 12])',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 3: MODULE C - Posture Keypoints (MobileNetV2) -> posture_keypoints.tflite
  // ===========================================================================
  Widget _buildModuleCTab() {
    final Color postureColor = _postureRisk > 0.50
        ? NasaColors.orbitRed
        : (_postureRisk > 0.30 ? NasaColors.warningAmber : NasaColors.capsuleGreen);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSpecBanner(
            title: 'MODULE C: posture_keypoints.tflite (MobileNetV2 0.35)',
            inputSpec: 'float32 [1, 224, 224, 3] RGB 0..255 (Rescaling is INSIDE model)',
            outputSpec: '4 Keypoints (0:ear, 1:upper, 2:mid, 3:low back) -> Risk [1, 1]',
          ),
          const SizedBox(height: 14),

          Center(
            child: Container(
              width: 224,
              height: 224,
              decoration: BoxDecoration(
                color: NasaColors.stationGrey,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: postureColor, width: 2),
              ),
              child: CustomPaint(
                painter: _PostureKeypointsPainter(
                  neckDevDeg: _neckDevDeg,
                  spineCurvDeg: _spineCurvDeg,
                  color: postureColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildSliderRow(
            label: 'Neck Deviation Angle (neck_dev: ok=15°, bad=45°)',
            value: _neckDevDeg,
            min: 5,
            max: 55,
            unit: 'deg',
            onChanged: (double v) {
              setState(() => _neckDevDeg = v);
              _evaluateModuleC(showToast: false);
            },
          ),
          _buildSliderRow(
            label: 'Spine Curvature Angle (spine_curv: ok=10°, bad=35°)',
            value: _spineCurvDeg,
            min: 5,
            max: 45,
            unit: 'deg',
            onChanged: (double v) {
              setState(() => _spineCurvDeg = v);
              _evaluateModuleC(showToast: false);
            },
          ),
          const SizedBox(height: 8),

          const Text(
            'POSTURE KEYPOINT PRESETS (melsmm/posture-keypoints-detection):',
            style: TextStyle(color: NasaColors.nebulaGrey, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            color: NasaColors.stationGrey,
            child: Column(
              children: [
                {
                  'name': 'Nominal Microgravity Neutral Posture',
                  'neck': 16.0,
                  'spine': 11.0,
                },
                {
                  'name': 'EVA Suit Lumbar & Neck Forward Strain',
                  'neck': 29.0,
                  'spine': 22.0,
                },
                {
                  'name': 'Severe 0G Slouch / Kyphotic Curvature',
                  'neck': 42.0,
                  'spine': 33.0,
                },
              ].map((Map<String, dynamic> item) {
                final String name = item['name'] as String;
                return ListTile(
                  leading: Icon(
                    _selectedPosturePreset == name
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: NasaColors.biometricCyan,
                  ),
                  title: Text(name, style: const TextStyle(fontSize: 12)),
                  onTap: () {
                    setState(() {
                      _selectedPosturePreset = name;
                      _neckDevDeg = item['neck'] as double;
                      _spineCurvDeg = item['spine'] as double;
                    });
                    _evaluateModuleC(showToast: true);
                  },
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: NasaColors.stationGrey,
              borderRadius: BorderRadius.circular(14),
              border: Border(left: BorderSide(color: postureColor, width: 5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ERGONOMIC POSTURE RISK [1, 1]:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  '${(_postureRisk * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: postureColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecBanner({
    required String title,
    required String inputSpec,
    required String outputSpec,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NasaColors.deepSpaceBlue.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NasaColors.biometricCyan.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: NasaColors.pureWhite,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text('• Input: $inputSpec', style: const TextStyle(color: NasaColors.biometricCyan, fontSize: 11)),
          Text('• Output: $outputSpec', style: const TextStyle(color: NasaColors.starlightWhite, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required String unit,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
            Text(
              '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)} $unit',
              style: const TextStyle(color: NasaColors.biometricCyan, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          activeColor: NasaColors.biometricCyan,
          inactiveColor: NasaColors.stationGrey,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildTierSelector({
    required String label,
    required int currentValue,
    required ValueChanged<int> onChanged,
  }) {
    const Map<int, String> labels = <int, String>{
      1: '1: Normal',
      2: '2: Above',
      3: '3: Well Above',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Row(
          children: <int>[1, 2, 3].map((int tier) {
            final bool selected = currentValue == tier;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(labels[tier]!, style: const TextStyle(fontSize: 11)),
                  selected: selected,
                  selectedColor: NasaColors.deepSpaceBlue,
                  onSelected: (_) => onChanged(tier),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _EcgWavePainter extends CustomPainter {
  final List<double> samples;

  _EcgWavePainter(this.samples);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint gridPaint = Paint()
      ..color = NasaColors.nebulaGrey.withValues(alpha: 0.15)
      ..strokeWidth = 1;

    for (double y = 0; y <= size.height; y += size.height / 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (samples.isEmpty) return;

    final Paint wavePaint = Paint()
      ..color = NasaColors.biometricCyan
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final Path path = Path();
    for (int i = 0; i < samples.length; i++) {
      final double x = (i / (samples.length - 1)) * size.width;
      final double y = size.height - (samples[i].clamp(0.0, 1.0) * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, wavePaint);
  }

  @override
  bool shouldRepaint(covariant _EcgWavePainter oldDelegate) => true;
}

/// posture_keypoints_train.py içindeki 4 omurga noktasını (0=ear, 1=upper, 2=mid, 3=lower) çizen Painter
class _PostureKeypointsPainter extends CustomPainter {
  final double neckDevDeg;
  final double spineCurvDeg;
  final Color color;

  _PostureKeypointsPainter({
    required this.neckDevDeg,
    required this.spineCurvDeg,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Offset lowBack = Offset(size.width * 0.45, size.height * 0.82);
    final Offset midBack = Offset(
      size.width * 0.45 - (spineCurvDeg * 0.45),
      size.height * 0.58,
    );
    final Offset upperBack = Offset(
      size.width * 0.45 + (spineCurvDeg * 0.30),
      size.height * 0.36,
    );
    final Offset earHead = Offset(
      upperBack.dx + (neckDevDeg * 0.65),
      size.height * 0.18,
    );

    final List<Offset> points = <Offset>[earHead, upperBack, midBack, lowBack];

    final Paint linePaint = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;

    final Path path = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy);
    canvas.drawPath(path, linePaint);

    final Paint dotPaint = Paint()..color = NasaColors.biometricCyan;
    for (final Offset pt in points) {
      canvas.drawCircle(pt, 5.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PostureKeypointsPainter oldDelegate) => true;
}