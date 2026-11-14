import 'package:flutter/material.dart';
import 'package:nasa_health_app/core/ml/ai_input_models.dart';
import 'package:nasa_health_app/core/theme/app_theme.dart';
import 'package:nasa_health_app/features/dashboard/screens/ai_diagnostics_screen.dart';
import 'package:nasa_health_app/features/dashboard/widgets/nasa_drawer.dart';

class MissionTaskItem {
  final String title;
  final String hazard;
  final int xp;
  bool done;

  MissionTaskItem({
    required this.title,
    required this.hazard,
    required this.xp,
    this.done = false,
  });
}

class BodyPartStatus {
  final String status;
  final Color color;
  final String hazard;
  final String insight;
  final String action;

  const BodyPartStatus({
    required this.status,
    required this.color,
    required this.hazard,
    required this.insight,
    required this.action,
  });
}

class SpaceEnvironmentProfile {
  final String name;
  final String gravityLabel;
  final double radiationMsvDay;
  final String radiationStatus;
  final Color radiationColor;
  final int baselineHrDelta;
  final String hazardSummary;

  const SpaceEnvironmentProfile({
    required this.name,
    required this.gravityLabel,
    required this.radiationMsvDay,
    required this.radiationStatus,
    required this.radiationColor,
    required this.baselineHrDelta,
    required this.hazardSummary,
  });
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final GlobalKey<AiDiagnosticsScreenState> _aiLabKey =
      GlobalKey<AiDiagnosticsScreenState>();

  int _selectedDrawerIndex = 0;
  String _selectedEnvironment = 'Deep Space Transit (0G)';
  String _selectedBodyPart = 'Cardiovascular (Heart)';

  int _liveHeartRate = 72;
  String _liveEcgStatus = '0 = N (Normal Beat)';
  Color _liveEcgColor = NasaColors.capsuleGreen;

  int _liveSystolic = 120;
  int _liveDiastolic = 80;
  double _liveCardioRisk = 0.17;

  double _livePostureRisk = 0.09;
  double _liveNeckDev = 18.0;

  double _liveRadiationMsv = 0.42;
  Color _liveRadiationColor = NasaColors.warningAmber;
  String _activeEngineBadge = 'AI READY';

  FaceStateResult _faceState = const FaceStateResult(
    smile: 0.72,
    eyeOpen: 0.88,
    fatigue: 0.12,
    headOffset: 0.08,
    stress: 0.16,
  );

  static const Map<String, SpaceEnvironmentProfile> _envProfiles =
      <String, SpaceEnvironmentProfile>{
    'Deep Space Transit (0G)': SpaceEnvironmentProfile(
      name: 'Deep Space Transit (0G)',
      gravityLabel: '0.00 G (Weightless)',
      radiationMsvDay: 1.15,
      radiationStatus: 'GCR HIGH RISK',
      radiationColor: NasaColors.orbitRed,
      baselineHrDelta: 8,
      hazardSummary: 'Galactic Cosmic Rays (GCR) + Fluid Shift to Head',
    ),
    'ISS Orbit (Micro-G)': SpaceEnvironmentProfile(
      name: 'ISS Orbit (Micro-G)',
      gravityLabel: 'Micro-G (LEO Shielded)',
      radiationMsvDay: 0.42,
      radiationStatus: 'MAGNETOSPHERE OK',
      radiationColor: NasaColors.capsuleGreen,
      baselineHrDelta: 0,
      hazardSummary: 'Protected by Earth Magnetosphere • Bone Loss Active',
    ),
    'Lunar Surface (1/6 G)': SpaceEnvironmentProfile(
      name: 'Lunar Surface (1/6 G)',
      gravityLabel: '0.16 G (Lunar Base)',
      radiationMsvDay: 0.68,
      radiationStatus: 'SOLAR SPE WARN',
      radiationColor: NasaColors.warningAmber,
      baselineHrDelta: 4,
      hazardSummary: 'Lunar Regolith Dust & EVA Suit Lumbar Strain',
    ),
    'Mars Habitat (3/8 G)': SpaceEnvironmentProfile(
      name: 'Mars Habitat (3/8 G)',
      gravityLabel: '0.38 G (Martian Base)',
      radiationMsvDay: 0.54,
      radiationStatus: 'ATMOS SHIELDING',
      radiationColor: NasaColors.biometricCyan,
      baselineHrDelta: 2,
      hazardSummary: '20-min Comm Delay (Autonomous AI Diagnosis Active)',
    ),
  };

  final List<MissionTaskItem> _missionTasks = <MissionTaskItem>[
    MissionTaskItem(
      title: 'ARED Resistive Squat & Deadlift (45 min)',
      hazard: 'Altered Gravity • Bone Loss Prevention',
      xp: 150,
      done: true,
    ),
    MissionTaskItem(
      title: '187-Sample MIT-BIH ECG Check (Module A)',
      hazard: 'Space Radiation • Arrhythmia Screening',
      xp: 100,
      done: false,
    ),
    MissionTaskItem(
      title: '4-Keypoint Spine Posture Scan (Module C)',
      hazard: 'Microgravity Spinal Elongation',
      xp: 120,
      done: false,
    ),
    MissionTaskItem(
      title: 'Circadian Blue-Light & Fatigue Protocol',
      hazard: 'Isolation & Confinement • Sleep Deficit',
      xp: 80,
      done: false,
    ),
  ];

  final Map<String, BodyPartStatus> _bodyPartData = <String, BodyPartStatus>{
    'Neurological (Head)': const BodyPartStatus(
      status: 'NOMINAL',
      color: NasaColors.capsuleGreen,
      hazard: 'Isolation & Space Radiation',
      insight: 'Eye-open alertness: 88% | Neurological stress score: 16%.',
      action: 'Continue circadian blue-light therapy for 20 mins.',
    ),
    'Cardiovascular (Heart)': const BodyPartStatus(
      status: 'NOMINAL',
      color: NasaColors.capsuleGreen,
      hazard: 'Module A (ECG) & Module B (Cardio)',
      insight: 'HR: 72 bpm (Normal N) | BP: 120/80 mmHg | Cardio Risk: 17.0%.',
      action: 'Tap Heart Rate or BP card below to update model inputs.',
    ),
    'Musculoskeletal (Spine)': const BodyPartStatus(
      status: 'OPTIMAL',
      color: NasaColors.capsuleGreen,
      hazard: 'Module C (4-Keypoint Posture)',
      insight: 'Posture Risk: 9.0% | Neck Deviation: 18.0°.',
      action: 'Complete ARED resistive protocol and monitor spine curvature.',
    ),
  };

  void _onEnvironmentChanged(String envName) {
    final SpaceEnvironmentProfile profile = _envProfiles[envName]!;
    setState(() {
      _selectedEnvironment = envName;
      _liveRadiationMsv = profile.radiationMsvDay;
      _liveRadiationColor = profile.radiationColor;
      _liveHeartRate = (72 + profile.baselineHrDelta).clamp(55, 165);

      _bodyPartData['Neurological (Head)'] = BodyPartStatus(
        status: profile.radiationMsvDay > 0.8 ? 'RADIATION ALERT' : 'NOMINAL',
        color: profile.radiationColor,
        hazard: '$envName • ${profile.gravityLabel}',
        insight:
            '${profile.hazardSummary} | Radiation: ${profile.radiationMsvDay.toStringAsFixed(2)} mSv/d.',
        action: profile.radiationMsvDay > 0.8
            ? 'Move to storm shelter module & run neurological check.'
            : 'Standard habitat shielding nominal.',
      );
    });
  }

  void _onAiModelsEvaluated(AiEvaluationBundle bundle) {
    setState(() {
      _liveHeartRate = bundle.heartRateBpm;
      _liveEcgStatus = bundle.dominantEcgClass;
      _liveEcgColor = bundle.ecgAnomalyRisk > 0.35
          ? NasaColors.orbitRed
          : NasaColors.capsuleGreen;

      _liveSystolic = bundle.systolic;
      _liveDiastolic = bundle.diastolic;
      _liveCardioRisk = bundle.cardioRisk;

      _livePostureRisk = bundle.postureRisk;
      _liveNeckDev = bundle.neckDevDeg;
      _activeEngineBadge = bundle.activeEngineLabel;

      final double combinedHeartRisk =
          (bundle.ecgAnomalyRisk * 0.5) + (bundle.cardioRisk * 0.5);
      _bodyPartData['Cardiovascular (Heart)'] = BodyPartStatus(
        status: combinedHeartRisk > 0.40 ? 'HIGH RISK' : 'NOMINAL',
        color: combinedHeartRisk > 0.40
            ? NasaColors.orbitRed
            : NasaColors.capsuleGreen,
        hazard: 'Module A (ECG) & Module B (Cardio)',
        insight:
            'HR: $_liveHeartRate bpm ($_liveEcgStatus) | BP: $_liveSystolic/$_liveDiastolic mmHg | Cardio Risk: ${(bundle.cardioRisk * 100).toStringAsFixed(1)}%',
        action: combinedHeartRisk > 0.40
            ? 'Alert Flight Surgeon & perform 12-lead resting ECG immediately.'
            : 'Cardiovascular parameters within nominal mission thresholds.',
      );

      _bodyPartData['Musculoskeletal (Spine)'] = BodyPartStatus(
        status: bundle.postureRisk > 0.40 ? 'POSTURE ALERT' : 'OPTIMAL',
        color: bundle.postureRisk > 0.40
            ? NasaColors.warningAmber
            : NasaColors.capsuleGreen,
        hazard: 'Module C (4-Keypoint Posture)',
        insight:
            'Ergonomic Risk: ${(bundle.postureRisk * 100).toStringAsFixed(1)}% | Neck Dev: ${bundle.neckDevDeg.toStringAsFixed(1)}° | Spine Curv: ${bundle.spineCurvDeg.toStringAsFixed(1)}°',
        action: bundle.postureRisk > 0.40
            ? 'Adjust harness tension and perform 30 min resistive spinal loading.'
            : 'Spinal alignment nominal for microgravity operations.',
      );
    });
  }

  void _openAiLabTab(int tabIndex) {
    setState(() => _selectedDrawerIndex = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _aiLabKey.currentState?.switchToTab(tabIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    const List<String> titles = <String>[
      'ASTRONAUT BIOMETRIC TWIN',
      'AI DIAGNOSTIC LAB (A / B / C)',
      'COUNTERMEASURES & HAZARDS',
    ];

    return Scaffold(
      drawer: NasaDrawer(
        selectedIndex: _selectedDrawerIndex,
        onItemSelected: (int index) {
          setState(() => _selectedDrawerIndex = index);
          Navigator.pop(context);
        },
      ),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titles[_selectedDrawerIndex],
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            Text(
              'ENV: $_selectedEnvironment • $_activeEngineBadge',
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 10, color: NasaColors.biometricCyan),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Open AI Lab',
            onPressed: () => setState(() => _selectedDrawerIndex = 1),
            icon:
                const Icon(Icons.memory_rounded, color: NasaColors.biometricCyan),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _selectedDrawerIndex,
          children: [
            _buildMainDashboardTab(),
            AiDiagnosticsScreen(
              key: _aiLabKey,
              onModelsEvaluated: _onAiModelsEvaluated,
            ),
            _buildCountermeasuresTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildMainDashboardTab() {
    final BodyPartStatus activePartInfo = _bodyPartData[_selectedBodyPart]!;
    final Color bpColor = _liveCardioRisk > 0.45
        ? NasaColors.orbitRed
        : (_liveCardioRisk > 0.28
            ? NasaColors.warningAmber
            : NasaColors.capsuleGreen);
    final Color postureColor = _livePostureRisk > 0.45
        ? NasaColors.orbitRed
        : (_livePostureRisk > 0.28
            ? NasaColors.warningAmber
            : NasaColors.capsuleGreen);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEnvironmentSelector(),
          const SizedBox(height: 16),
          _build3DBodyViewportPlaceholder(activePartInfo),
          const SizedBox(height: 16),
          _buildDiagnosticActionCard(activePartInfo),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'LIVE TELEMETRY (TAP ANY CARD TO EDIT)',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: NasaColors.pureWhite,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _openAiLabTab(0),
                icon: const Icon(Icons.tune_rounded,
                    color: NasaColors.biometricCyan, size: 16),
                label: const Text(
                  'AI LAB (A/B/C)',
                  style:
                      TextStyle(color: NasaColors.biometricCyan, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.38,
            children: [
              _VitalMetricCard(
                title: 'HEART RATE (MODULE A)',
                value: '$_liveHeartRate',
                unit: 'bpm',
                statusText: _liveEcgStatus,
                statusColor: _liveEcgColor,
                icon: Icons.favorite_rounded,
                onTap: _showQuickHeartModal,
              ),
              _VitalMetricCard(
                title: 'BLOOD PRESSURE (B)',
                value: '$_liveSystolic/$_liveDiastolic',
                unit: 'mmHg',
                statusText:
                    'RISK: ${(_liveCardioRisk * 100).toStringAsFixed(0)}%',
                statusColor: bpColor,
                icon: Icons.speed_rounded,
                onTap: _showQuickBpModal,
              ),
              _VitalMetricCard(
                title: 'SPINE POSTURE (C)',
                value: '${_liveNeckDev.toStringAsFixed(0)}°',
                unit: '224² RGB',
                statusText:
                    'RISK: ${(_livePostureRisk * 100).toStringAsFixed(0)}%',
                statusColor: postureColor,
                icon: Icons.accessibility_new_rounded,
                onTap: () => _openAiLabTab(2),
              ),
              _VitalMetricCard(
                title: 'RADIATION & STRESS',
                value: _liveRadiationMsv.toStringAsFixed(2),
                unit: 'mSv/d',
                statusText:
                    'STRESS: ${(_faceState.stress * 100).toStringAsFixed(0)}%',
                statusColor: _liveRadiationColor,
                icon: Icons.radar_rounded,
                onTap: _showFaceAndRadiationModal,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showQuickHeartModal() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NasaColors.stationGrey,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) {
        int tempHr = _liveHeartRate;
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'QUICK INPUT: HEART RATE & MODULE A (ECG)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Current Heart Rate: $tempHr bpm',
                    style: const TextStyle(
                        color: NasaColors.biometricCyan, fontSize: 14),
                  ),
                  Slider(
                    value: tempHr.toDouble(),
                    min: 50,
                    max: 165,
                    activeColor: NasaColors.biometricCyan,
                    onChanged: (double v) =>
                        setModalState(() => tempHr = v.round()),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _openAiLabTab(0);
                          },
                          child: const Text('187-SAMPLE ECG LAB'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: NasaColors.biometricCyan,
                            foregroundColor: NasaColors.darkMatter,
                          ),
                          onPressed: () {
                            setState(() {
                              _liveHeartRate = tempHr;
                              _liveEcgStatus = tempHr > 100
                                  ? '1 = S (Tachycardia)'
                                  : (tempHr < 58
                                      ? 'Bradycardia'
                                      : '0 = N (Normal)');
                              _liveEcgColor = (tempHr > 100 || tempHr < 58)
                                  ? NasaColors.orbitRed
                                  : NasaColors.capsuleGreen;
                              _selectedBodyPart = 'Cardiovascular (Heart)';
                              _bodyPartData['Cardiovascular (Heart)'] =
                                  BodyPartStatus(
                                status: _liveEcgStatus,
                                color: _liveEcgColor,
                                hazard: 'Manual Telemetry + ecg_heartbeat.keras',
                                insight:
                                    'Updated HR: $_liveHeartRate bpm | BP: $_liveSystolic/$_liveDiastolic mmHg.',
                                action: tempHr > 100
                                    ? 'Run 187-sample ECG check in Module A immediately.'
                                    : 'Heart rate within nominal mission limits.',
                              );
                            });
                            Navigator.pop(ctx);
                          },
                          child: const Text('APPLY'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showQuickBpModal() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NasaColors.stationGrey,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) {
        int tempSys = _liveSystolic;
        int tempDia = _liveDiastolic;
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'QUICK INPUT: BLOOD PRESSURE (MODULE B)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  Text('Systolic BP (ap_hi): $tempSys mmHg'),
                  Slider(
                    value: tempSys.toDouble(),
                    min: 90,
                    max: 195,
                    activeColor: NasaColors.biometricCyan,
                    onChanged: (double v) {
                      setModalState(() {
                        tempSys = v.round();
                        if (tempSys <= tempDia) tempDia = tempSys - 15;
                      });
                    },
                  ),
                  Text('Diastolic BP (ap_lo): $tempDia mmHg'),
                  Slider(
                    value: tempDia.toDouble(),
                    min: 55,
                    max: 125,
                    activeColor: NasaColors.biometricCyan,
                    onChanged: (double v) {
                      setModalState(() {
                        tempDia = v.round();
                        if (tempDia >= tempSys) tempSys = tempDia + 15;
                      });
                    },
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _openAiLabTab(1);
                          },
                          child: const Text('ALL 12 FEATURES'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: NasaColors.biometricCyan,
                            foregroundColor: NasaColors.darkMatter,
                          ),
                          onPressed: () async {
                            final CardioModelInput input = CardioModelInput(
                              ageYears: 38.0,
                              gender: 2,
                              heightCm: 176.0,
                              weightKg: 75.0,
                              apHi: tempSys.toDouble(),
                              apLo: tempDia.toDouble(),
                              cholesterol: 1,
                              gluc: 1,
                              smoke: 0,
                              alco: 0,
                              active: 1,
                            );
                            final CardioPredictionResult res =
                                await NasaAiService.runCardioModel(input);
                            if (!mounted) return;
                            setState(() {
                              _liveSystolic = tempSys;
                              _liveDiastolic = tempDia;
                              _liveCardioRisk = res.risk;
                              _selectedBodyPart = 'Cardiovascular (Heart)';
                              _bodyPartData['Cardiovascular (Heart)'] =
                                  BodyPartStatus(
                                status:
                                    res.risk > 0.40 ? 'HIGH RISK' : 'NOMINAL',
                                color: res.risk > 0.40
                                    ? NasaColors.orbitRed
                                    : NasaColors.capsuleGreen,
                                hazard: res.engineUsed,
                                insight:
                                    'BP: $_liveSystolic/$_liveDiastolic mmHg | Module B Risk: ${(res.risk * 100).toStringAsFixed(1)}%.',
                                action: res.risk > 0.40
                                    ? 'Reduce sodium intake & monitor cuff pressure every 4h.'
                                    : 'Blood pressure optimal.',
                              );
                            });
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          child: const Text('RUN MODULE B'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showFaceAndRadiationModal() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NasaColors.stationGrey,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) {
        double smile = _faceState.smile;
        double eyeOpen = _faceState.eyeOpen;
        double headTilt = _faceState.headOffset;
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final double fatigue = (1.0 - eyeOpen).clamp(0.0, 1.0);
            final double stress =
                (0.4 * (1.0 - smile) + 0.4 * fatigue + 0.2 * headTilt)
                    .clamp(0.0, 1.0);

            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'NEUROLOGICAL FATIGUE & STRESS PARAMETERS',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Fatigue: ${(fatigue * 100).toStringAsFixed(0)}% | Stress Score: ${(stress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                        color: NasaColors.biometricCyan, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Text('Smile Probability: ${(smile * 100).toStringAsFixed(0)}%'),
                  Slider(
                    value: smile,
                    onChanged: (double v) => setModalState(() => smile = v),
                    activeColor: NasaColors.capsuleGreen,
                  ),
                  Text(
                      'Eye-Open Alertness: ${(eyeOpen * 100).toStringAsFixed(0)}%'),
                  Slider(
                    value: eyeOpen,
                    onChanged: (double v) => setModalState(() => eyeOpen = v),
                    activeColor: NasaColors.biometricCyan,
                  ),
                  Text(
                      'Head Tilt Offset: ${(headTilt * 40).toStringAsFixed(0)}°'),
                  Slider(
                    value: headTilt,
                    onChanged: (double v) => setModalState(() => headTilt = v),
                    activeColor: NasaColors.warningAmber,
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NasaColors.biometricCyan,
                        foregroundColor: NasaColors.darkMatter,
                      ),
                      onPressed: () {
                        setState(() {
                          _faceState = FaceStateResult(
                            smile: smile,
                            eyeOpen: eyeOpen,
                            fatigue: fatigue,
                            headOffset: headTilt,
                            stress: stress,
                          );
                          _selectedBodyPart = 'Neurological (Head)';
                          _bodyPartData['Neurological (Head)'] = BodyPartStatus(
                            status: stress > 0.45 ? 'HIGH FATIGUE' : 'NOMINAL',
                            color: stress > 0.45
                                ? NasaColors.orbitRed
                                : NasaColors.capsuleGreen,
                            hazard: 'Isolation & Sleep Deficit',
                            insight:
                                'Fatigue: ${(fatigue * 100).toStringAsFixed(0)}% | Stress: ${(stress * 100).toStringAsFixed(0)}%.',
                            action: stress > 0.45
                                ? 'Mandatory 8h sleep cycle & behavioral check-in.'
                                : 'Cognitive alertness nominal.',
                          );
                        });
                        Navigator.pop(ctx);
                      },
                      child: const Text('UPDATE NEUROLOGICAL STATUS'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCountermeasuresTab() {
    int totalXp = 0;
    for (final MissionTaskItem t in _missionTasks) {
      if (t.done) totalXp += t.xp;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: NasaColors.stationGrey,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: NasaColors.biometricCyan.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CREW HEALTH ADHERENCE SCORE',
                      style:
                          TextStyle(color: NasaColors.nebulaGrey, fontSize: 11),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'LEVEL 8 • MISSION READY',
                      style: TextStyle(
                        color: NasaColors.pureWhite,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: NasaColors.deepSpaceBlue,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$totalXp XP',
                    style: const TextStyle(
                      color: NasaColors.biometricCyan,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'DAILY COUNTERMEASURE PROTOCOLS',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8),
          ),
          const SizedBox(height: 10),
          ...List<Widget>.generate(_missionTasks.length, (int i) {
            final MissionTaskItem task = _missionTasks[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: CheckboxListTile(
                value: task.done,
                activeColor: NasaColors.capsuleGreen,
                title: Text(
                  task.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    decoration: task.done
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
                subtitle: Text(
                  '${task.hazard}  •  +${task.xp} XP',
                  style: const TextStyle(
                      color: NasaColors.biometricCyan, fontSize: 11),
                ),
                onChanged: (bool? v) =>
                    setState(() => _missionTasks[i].done = v ?? false),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEnvironmentSelector() {
    final List<String> envNames = _envProfiles.keys.toList();
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: envNames.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final String env = envNames[index];
          final bool isSelected = env == _selectedEnvironment;
          return ChoiceChip(
            label: Text(env),
            selected: isSelected,
            onSelected: (bool selected) => _onEnvironmentChanged(env),
            backgroundColor: NasaColors.stationGrey,
            selectedColor: NasaColors.deepSpaceBlue,
            labelStyle: TextStyle(
              color: isSelected ? NasaColors.pureWhite : NasaColors.nebulaGrey,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
            side: BorderSide(
              color: isSelected ? NasaColors.biometricCyan : Colors.transparent,
            ),
          );
        },
      ),
    );
  }

  Widget _build3DBodyViewportPlaceholder(BodyPartStatus activePartInfo) {
    final Color activeColor = activePartInfo.color;
    final SpaceEnvironmentProfile envProfile =
        _envProfiles[_selectedEnvironment]!;

    return Container(
      height: 290,
      width: double.infinity,
      decoration: BoxDecoration(
        color: NasaColors.stationGrey,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: activeColor.withValues(alpha: 0.6), width: 1.5),
        gradient: RadialGradient(
          colors: [
            activeColor.withValues(alpha: 0.18),
            NasaColors.stationGrey,
            NasaColors.darkMatter,
          ],
          radius: 0.85,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 12,
            left: 14,
            right: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'TARGET: ${_selectedBodyPart.toUpperCase()}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: NasaColors.pureWhite,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  envProfile.gravityLabel,
                  style: const TextStyle(
                      color: NasaColors.biometricCyan, fontSize: 11),
                ),
              ],
            ),
          ),
          Center(
            child: Icon(
              Icons.accessibility_new_rounded,
              size: 135,
              color: activeColor.withValues(alpha: 0.85),
            ),
          ),
          Positioned(
            bottom: 12,
            left: 10,
            right: 10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _bodyPartData.keys.map((String partName) {
                final bool isSelected = _selectedBodyPart == partName;
                final Color partColor = _bodyPartData[partName]!.color;
                return GestureDetector(
                  onTap: () => setState(() => _selectedBodyPart = partName),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? partColor.withValues(alpha: 0.25)
                          : NasaColors.darkMatter.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? partColor
                            : NasaColors.nebulaGrey.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      partName.split(' ').first,
                      style: TextStyle(
                        color: isSelected
                            ? NasaColors.pureWhite
                            : NasaColors.nebulaGrey,
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticActionCard(BodyPartStatus info) {
    final Color statusColor = info.color;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NasaColors.stationGrey,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: statusColor, width: 5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  info.hazard.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: NasaColors.biometricCyan,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  info.status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            info.insight,
            style: const TextStyle(color: NasaColors.pureWhite, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            'ACTION: ${info.action}',
            style: const TextStyle(color: NasaColors.nebulaGrey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _VitalMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final String statusText;
  final Color statusColor;
  final IconData icon;
  final VoidCallback onTap;

  const _VitalMetricCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.statusText,
    required this.statusColor,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: NasaColors.nebulaGrey,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Icon(icon, color: NasaColors.biometricCyan, size: 15),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: NasaColors.pureWhite,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(unit,
                      style: const TextStyle(
                          color: NasaColors.nebulaGrey, fontSize: 11)),
                ],
              ),
              Row(
                children: [
                  Icon(Icons.circle, color: statusColor, size: 8),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      statusText,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Icon(Icons.edit_outlined,
                      color: NasaColors.nebulaGrey, size: 12),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}