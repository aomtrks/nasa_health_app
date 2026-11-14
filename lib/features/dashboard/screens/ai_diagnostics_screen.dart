import 'package:flutter/material.dart';
import 'package:nasa_health_app/core/ml/ai_input_models.dart';
import 'package:nasa_health_app/core/ml/health_ai_service.dart';
import 'package:nasa_health_app/core/theme/app_theme.dart';

class AiDiagnosticsScreen extends StatefulWidget {
  final void Function(double ecgRisk, double cardioRisk, double postureRisk)? onModelsEvaluated;

  const AiDiagnosticsScreen({super.key, this.onModelsEvaluated});

  @override
  State<AiDiagnosticsScreen> createState() => _AiDiagnosticsScreenState();
}

class _AiDiagnosticsScreenState extends State<AiDiagnosticsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final HealthAiService _ai = HealthAiService();
  bool _aiReady = false;

  // --- MODEL A (ECG [1, 187, 1]) STATE ---
  String _selectedEcgPreset = 'Normal Sinus Rhythm';
  late List<double> _ecgSamples;
  final TextEditingController _ecgRawController = TextEditingController();
  List<double> _ecgOutputProbs = <double>[0.88, 0.05, 0.03, 0.02, 0.02];

  // --- MODEL B (CARDIO [1, 12]) STATE ---
  double _age = 36;
  int _gender = 1; // 1: Male, 0: Female
  double _height = 178;
  double _weight = 76;
  double _systolic = 122;
  double _diastolic = 80;
  int _cholesterol = 1; // 1, 2, 3
  int _glucose = 1; // 1, 2, 3
  bool _smoke = false;
  bool _alcohol = false;
  bool _active = true;
  double _cardioRiskOutput = 0.18;

  // --- MODEL C (POSTURE [1, 224, 224, 3]) STATE ---
  String _selectedPostureSource = 'Microgravity Neutral Spine (Nominal)';
  bool _isTensorReady = true;
  double _postureRiskOutput = 0.14;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadEcgPreset(_selectedEcgPreset);
    _initAi();
  }

  Future<void> _initAi() async {
    try {
      await _ai.load();
      if (!mounted) return;
      setState(() => _aiReady = true);
      _evalA();
      _evalB();
      _evalC();
      _notifyDashboard();
    } catch (e) {
      if (!mounted) return;
      _showMsg('Model load error: $e');
    }
  }

  void _showMsg(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: NasaColors.deepSpaceBlue, content: Text(text)),
    );
  }

  List<double> _parseEcg() {
    final List<double> parts = _ecgRawController.text
        .split(',')
        .map((String e) => double.tryParse(e.trim()) ?? 0.0)
        .toList();
    return List<double>.generate(
      187,
      (int i) => i < parts.length ? parts[i].clamp(0.0, 1.0).toDouble() : 0.0,
    );
  }

  CardioModelInput _cardioInput() => CardioModelInput(
        ageYears: _age,
        gender: _gender,
        heightCm: _height,
        weightKg: _weight,
        systolicBp: _systolic,
        diastolicBp: _diastolic,
        cholesterol: _cholesterol,
        glucose: _glucose,
        smoke: _smoke ? 1 : 0,
        alcohol: _alcohol ? 1 : 0,
        active: _active ? 1 : 0,
      );

  void _evalA() {
    final List<double> samples = _parseEcg();
    final List<double> probs = _ai.runEcg(samples);
    setState(() {
      _ecgSamples = samples;
      _ecgOutputProbs = probs;
    });
  }

  void _evalB() {
    final double risk = _ai.runCardio(_cardioInput());
    setState(() => _cardioRiskOutput = risk);
  }

  void _evalC() {
    final tensor = PostureModelInput.createFloat32ImageTensor(null);
    final double risk = _ai.runPosture(tensor);
    setState(() {
      _isTensorReady = tensor.length == 224 * 224 * 3;
      _postureRiskOutput = risk;
    });
  }

  void _loadEcgPreset(String preset) {
    final List<double> samples = EcgModelInput.generatePreset(preset);
    setState(() {
      _selectedEcgPreset = preset;
      _ecgSamples = samples;
      _ecgRawController.text = samples.join(', ');
    });
  }

  void _runModelA() {
    if (!_aiReady) return _showMsg('Models are still loading...');
    _evalA();
    _notifyDashboard();
    final int top = _ecgOutputProbs.indexOf(_ecgOutputProbs.reduce((x, y) => x > y ? x : y));
    const List<String> names = <String>['N', 'S', 'V', 'F', 'Q'];
    _showMsg('Model A: class ${names[top]} '
        '(${(_ecgOutputProbs[top] * 100).toStringAsFixed(1)}%)');
  }

  void _runModelB() {
    if (!_aiReady) return _showMsg('Models are still loading...');
    _evalB();
    _notifyDashboard();
    _showMsg('Model B: cardiovascular risk ${(_cardioRiskOutput * 100).toStringAsFixed(1)}%');
  }

  void _runModelC() {
    if (!_aiReady) return _showMsg('Models are still loading...');
    _evalC();
    _notifyDashboard();
    _showMsg('Model C: posture risk ${(_postureRiskOutput * 100).toStringAsFixed(1)}%');
  }

  void _notifyDashboard() {
    final double ecgAnomalyRisk = 1.0 - _ecgOutputProbs[0];
    widget.onModelsEvaluated?.call(ecgAnomalyRisk, _cardioRiskOutput, _postureRiskOutput);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ai.dispose();
    _ecgRawController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: NasaColors.stationGrey,
          child: TabBar(
            controller: _tabController,
            indicatorColor: NasaColors.biometricCyan,
            labelColor: NasaColors.biometricCyan,
            unselectedLabelColor: NasaColors.nebulaGrey,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            tabs: const [
              Tab(text: 'MODEL A: ECG\n[1, 187, 1]'),
              Tab(text: 'MODEL B: CARDIO\n[1, 12]'),
              Tab(text: 'MODEL C: POSTURE\n[1, 224, 224, 3]'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildModelATab(),
              _buildModelBTab(),
              _buildModelCTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModelATab() {
    const List<String> classLabels = <String>[
      'N (Normal Beat)',
      'S (Supraventricular)',
      'V (Ventricular / PVC)',
      'F (Fusion Beat)',
      'Q (Unclassified)',
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSpecBanner(
            title: 'MODEL A: SINGLE HEARTBEAT ECG CLASSIFIER',
            inputSpec: 'float32 [1, 187, 1] (scaled 0.0–1.0)',
            outputSpec: 'float32 [1, 5] (class probabilities)',
          ),
          const SizedBox(height: 16),
          Container(
            height: 140,
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NasaColors.stationGrey,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: NasaColors.biometricCyan.withValues(alpha: 0.4)),
            ),
            child: CustomPaint(
              painter: _EcgWavePainter(_ecgSamples),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'LOAD TELEMETRY PRESET (187 SAMPLES):',
            style: TextStyle(color: NasaColors.nebulaGrey, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <String>[
              'Normal Sinus Rhythm',
              'Arrhythmia (PVC)',
              'Space Radiation Stress',
            ].map((String preset) {
              final bool selected = _selectedEcgPreset == preset;
              return ChoiceChip(
                label: Text(preset, style: const TextStyle(fontSize: 12)),
                selected: selected,
                selectedColor: NasaColors.deepSpaceBlue,
                backgroundColor: NasaColors.stationGrey,
                onSelected: (_) => _loadEcgPreset(preset),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ecgRawController,
            maxLines: 3,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText: '187 Scaled ECG Samples (0.0 - 1.0, comma separated)',
              labelStyle: const TextStyle(color: NasaColors.biometricCyan, fontSize: 12),
              filled: true,
              fillColor: NasaColors.stationGrey,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
              onPressed: _runModelA,
              icon: const Icon(Icons.monitor_heart_rounded),
              label: const Text(
                'RUN MODEL A ([1, 187, 1] FLOAT32)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'OUTPUT PROBABILITIES — SHAPE [1, 5]:',
            style: TextStyle(color: NasaColors.pureWhite, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 10),
          ...List<Widget>.generate(5, (int index) {
            final double prob = _ecgOutputProbs[index];
            final bool isNormal = index == 0;
            final Color barColor = isNormal ? NasaColors.capsuleGreen : NasaColors.orbitRed;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(classLabels[index], style: const TextStyle(fontSize: 12)),
                      Text(
                        '${(prob * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: barColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
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

  Widget _buildModelBTab() {
    final CardioModelInput currentInput = CardioModelInput(
      ageYears: _age,
      gender: _gender,
      heightCm: _height,
      weightKg: _weight,
      systolicBp: _systolic,
      diastolicBp: _diastolic,
      cholesterol: _cholesterol,
      glucose: _glucose,
      smoke: _smoke ? 1 : 0,
      alcohol: _alcohol ? 1 : 0,
      active: _active ? 1 : 0,
    );

    final Color riskColor = _cardioRiskOutput > 0.5
        ? NasaColors.orbitRed
        : (_cardioRiskOutput > 0.3 ? NasaColors.warningAmber : NasaColors.capsuleGreen);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSpecBanner(
            title: 'MODEL B: CARDIOVASCULAR RISK EVALUATOR',
            inputSpec: 'float32 [1, 12] (JSON Scaler Standardized)',
            outputSpec: 'float32 [1, 1] (Risk Score 0.0–1.0)',
          ),
          const SizedBox(height: 16),
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
                      '${(_cardioRiskOutput * 100).toStringAsFixed(1)}% (${_cardioRiskOutput.toStringAsFixed(3)})',
                      style: TextStyle(
                        color: riskColor,
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
                      'AUTO-COMPUTED BMI',
                      style: TextStyle(color: NasaColors.nebulaGrey, fontSize: 10),
                    ),
                    Text(
                      '${currentInput.bmi.toStringAsFixed(1)} kg/m²',
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
          const SizedBox(height: 16),
          _buildSliderRow(
            label: '1. Age (Years)',
            value: _age,
            min: 20,
            max: 70,
            unit: 'yrs',
            onChanged: (double v) => setState(() => _age = v.roundToDouble()),
          ),
          Row(
            children: [
              const Expanded(
                child: Text('2. Biological Sex:', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              ChoiceChip(
                label: const Text('Female (0)'),
                selected: _gender == 0,
                onSelected: (_) => setState(() => _gender = 0),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Male (1)'),
                selected: _gender == 1,
                onSelected: (_) => setState(() => _gender = 1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildSliderRow(
            label: '3. Height',
            value: _height,
            min: 140,
            max: 210,
            unit: 'cm',
            onChanged: (double v) => setState(() => _height = v.roundToDouble()),
          ),
          _buildSliderRow(
            label: '4. Weight',
            value: _weight,
            min: 45,
            max: 130,
            unit: 'kg',
            onChanged: (double v) => setState(() => _weight = v.roundToDouble()),
          ),
          _buildSliderRow(
            label: '5. Systolic BP',
            value: _systolic,
            min: 80,
            max: 200,
            unit: 'mmHg',
            onChanged: (double v) => setState(() => _systolic = v.roundToDouble()),
          ),
          _buildSliderRow(
            label: '6. Diastolic BP',
            value: _diastolic,
            min: 50,
            max: 130,
            unit: 'mmHg',
            onChanged: (double v) => setState(() => _diastolic = v.roundToDouble()),
          ),
          const SizedBox(height: 8),
          _buildTierSelector(
            label: '7. Cholesterol Level',
            currentValue: _cholesterol,
            onChanged: (int v) => setState(() => _cholesterol = v),
          ),
          const SizedBox(height: 10),
          _buildTierSelector(
            label: '8. Glucose Level',
            currentValue: _glucose,
            onChanged: (int v) => setState(() => _glucose = v),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: NasaColors.stationGrey,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('9. Smoking History (smoke)', style: TextStyle(fontSize: 13)),
                  value: _smoke,
                  activeThumbColor: NasaColors.orbitRed,
                  onChanged: (bool v) => setState(() => _smoke = v),
                ),
                SwitchListTile(
                  title: const Text('10. Alcohol Intake (alcohol)', style: TextStyle(fontSize: 13)),
                  value: _alcohol,
                  activeThumbColor: NasaColors.warningAmber,
                  onChanged: (bool v) => setState(() => _alcohol = v),
                ),
                SwitchListTile(
                  title: const Text('11. Physical Activity / ARED (active)', style: TextStyle(fontSize: 13)),
                  value: _active,
                  activeThumbColor: NasaColors.capsuleGreen,
                  onChanged: (bool v) => setState(() => _active = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: NasaColors.biometricCyan,
                foregroundColor: NasaColors.darkMatter,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _runModelB,
              icon: const Icon(Icons.calculate_rounded),
              label: const Text(
                'STANDARDIZE & RUN MODEL B ([1, 12] FLOAT32)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelCTab() {
    final Color postureColor = _postureRiskOutput > 0.5
        ? NasaColors.orbitRed
        : (_postureRiskOutput > 0.3 ? NasaColors.warningAmber : NasaColors.capsuleGreen);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSpecBanner(
            title: 'MODEL C: MICROGRAVITY POSTURE & SPINE ANALYZER',
            inputSpec: 'float32 [1, 224, 224, 3] (RGB 0.0–255.0)',
            outputSpec: 'float32 [1, 1] (Posture Risk 0.0–1.0)',
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              width: 224,
              height: 224,
              decoration: BoxDecoration(
                color: NasaColors.stationGrey,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: postureColor, width: 2),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.accessibility_new_rounded,
                    size: 130,
                    color: postureColor.withValues(alpha: 0.75),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: NasaColors.darkMatter.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '224x224 RGB • FLOAT32 (0-255)',
                        style: TextStyle(color: NasaColors.biometricCyan, fontSize: 9),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    child: Text(
                      _isTensorReady ? 'TENSOR READY: 150,528 FLOATS' : 'NO FRAME',
                      style: const TextStyle(
                        color: NasaColors.starlightWhite,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'SELECT CAMERA FEED / TEST FRAME:',
            style: TextStyle(color: NasaColors.nebulaGrey, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...<String>[
            'Microgravity Neutral Spine (Nominal)',
            'EVA Suit Lumbar Overload (Moderate Risk)',
            '0G Spinal Elongation / Kyphosis (High Risk)',
          ].map((String source) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _selectedPostureSource == source
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: NasaColors.biometricCyan,
              ),
              title: Text(source, style: const TextStyle(fontSize: 13)),
              onTap: () => setState(() => _selectedPostureSource = source),
            );
          }),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: NasaColors.biometricCyan,
                foregroundColor: NasaColors.darkMatter,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _runModelC,
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text(
                'CAPTURE & RUN MODEL C ([1, 224, 224, 3])',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
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
                  'POSTURE ANOMALY RISK [1, 1]:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  '${(_postureRiskOutput * 100).toStringAsFixed(1)}%',
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
              fontSize: 13,
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
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            Text(
              '${value.toInt()} $unit',
              style: const TextStyle(color: NasaColors.biometricCyan, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Slider(
          value: value,
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
      2: '2: Above Normal',
      3: '3: High',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
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