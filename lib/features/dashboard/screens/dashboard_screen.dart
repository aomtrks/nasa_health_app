import 'package:flutter/material.dart';
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

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedDrawerIndex = 0;
  String _selectedEnvironment = 'Deep Space Transit (0G)';
  String _selectedBodyPart = 'Cardiovascular (Heart)';

  final List<MissionTaskItem> _missionTasks = <MissionTaskItem>[
    MissionTaskItem(
      title: 'ARED Resistive Squat & Deadlift (45 min)',
      hazard: 'Altered Gravity • Bone Loss Prevention',
      xp: 150,
      done: true,
    ),
    MissionTaskItem(
      title: '187-Sample Single-Lead ECG Check (Model A)',
      hazard: 'Space Radiation • Arrhythmia Screening',
      xp: 100,
      done: false,
    ),
    MissionTaskItem(
      title: '224x224 RGB Spine Posture Scan (Model C)',
      hazard: 'Microgravity Spinal Elongation',
      xp: 120,
      done: false,
    ),
    MissionTaskItem(
      title: 'Circadian Blue-Light Therapy (20 min)',
      hazard: 'Isolation & Confinement • Sleep Deficit',
      xp: 80,
      done: false,
    ),
  ];

  final List<String> _environments = const <String>[
    'Deep Space Transit (0G)',
    'ISS Orbit (Micro-G)',
    'Lunar Surface (1/6 G)',
    'Mars Habitat (3/8 G)',
  ];

  final Map<String, BodyPartStatus> _bodyPartData = <String, BodyPartStatus>{
    'Neurological (Head)': const BodyPartStatus(
      status: 'NOMINAL',
      color: NasaColors.capsuleGreen,
      hazard: 'Isolation & Fluid Shift',
      insight: 'Intracranial pressure stable. Sleep efficiency at 88%.',
      action: 'Continue circadian light therapy for 20 mins.',
    ),
    'Cardiovascular (Heart)': const BodyPartStatus(
      status: 'ELEVATED STRESS',
      color: NasaColors.orbitRed,
      hazard: 'Model A (ECG) & Model B (Cardio)',
      insight: 'Model B Risk: 18% | Resting HR 86 bpm. Mild radiation-induced stress.',
      action: 'Run 187-sample ECG in AI Diagnostic Lab & reduce aerobic load.',
    ),
    'Musculoskeletal (Spine)': const BodyPartStatus(
      status: 'CAUTION',
      color: NasaColors.warningAmber,
      hazard: 'Model C (Posture 224x224)',
      insight: 'Microgravity spinal elongation detected. Lower lumbar tension.',
      action: 'Complete ARED resistive protocol and capture posture frame.',
    ),
  };

  void _updateFromAiModels(AiEvaluationBundle ai) {
    final double ecgRisk = ai.ecgAnomalyRisk;
    final double cardioRisk = ai.cardioRisk;
    final double postureRisk = ai.postureRisk;
    setState(() {
      final double combinedHeartRisk = (ecgRisk * 0.5) + (cardioRisk * 0.5);
      _bodyPartData['Cardiovascular (Heart)'] = BodyPartStatus(
        status: combinedHeartRisk > 0.45 ? 'HIGH RISK' : 'NOMINAL',
        color: combinedHeartRisk > 0.45 ? NasaColors.orbitRed : NasaColors.capsuleGreen,
        hazard: 'Model A (ECG) & Model B (Cardio)',
        insight:
            'AI Updated -> ECG Anomaly: ${(ecgRisk * 100).toStringAsFixed(0)}% (${ai.dominantEcgClass}, ~${ai.heartRateBpm} bpm) | Cardio Risk: ${(cardioRisk * 100).toStringAsFixed(0)}% (BP ${ai.systolic}/${ai.diastolic}, BMI ${ai.bmi.toStringAsFixed(1)})',
        action: combinedHeartRisk > 0.45
            ? 'Alert Flight Surgeon & perform 12-lead resting ECG immediately.'
            : 'Cardiovascular parameters within nominal mission thresholds.',
      );

      _bodyPartData['Musculoskeletal (Spine)'] = BodyPartStatus(
        status: postureRisk > 0.45 ? 'POSTURE ALERT' : 'OPTIMAL',
        color: postureRisk > 0.45 ? NasaColors.warningAmber : NasaColors.capsuleGreen,
        hazard: 'Model C (224x224 RGB Posture)',
        insight: 'AI Posture Risk: ${(postureRisk * 100).toStringAsFixed(1)}% | neck ${ai.neckDevDeg.toStringAsFixed(0)}°, spine ${ai.spineCurvDeg.toStringAsFixed(0)}° | ${ai.activeEngineLabel}',
        action: postureRisk > 0.45
            ? 'Adjust harness tension and perform 30 min resistive spinal loading.'
            : 'Spinal alignment nominal for microgravity operations.',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    const List<String> titles = <String>[
      'ASTRONAUT BIOMETRIC TWIN',
      'AI DIAGNOSTIC LAB (FLOAT32)',
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
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.0),
            ),
            Text(
              'ENV: $_selectedEnvironment',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: NasaColors.biometricCyan),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Open AI Lab',
            onPressed: () => setState(() => _selectedDrawerIndex = 1),
            icon: const Icon(Icons.memory_rounded, color: NasaColors.biometricCyan),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _selectedDrawerIndex,
          children: [
            _buildMainDashboardTab(),
            AiDiagnosticsScreen(onModelsEvaluated: _updateFromAiModels),
            _buildCountermeasuresTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildMainDashboardTab() {
    final BodyPartStatus activePartInfo = _bodyPartData[_selectedBodyPart]!;

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
                  'LIVE TELEMETRY & AI INPUTS',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: NasaColors.pureWhite,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _selectedDrawerIndex = 1),
                icon: const Icon(Icons.tune_rounded, color: NasaColors.biometricCyan, size: 16),
                label: const Text(
                  'INPUT A/B/C DATA',
                  style: TextStyle(color: NasaColors.biometricCyan, fontSize: 11),
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
            childAspectRatio: 1.4,
            children: const [
              _VitalMetricCard(
                title: 'HEART RATE (MODEL A)',
                value: '86',
                unit: 'bpm',
                statusText: '187 SAMPLES READY',
                statusColor: NasaColors.orbitRed,
                icon: Icons.favorite_rounded,
              ),
              _VitalMetricCard(
                title: 'BLOOD PRESSURE (B)',
                value: '122/80',
                unit: 'mmHg',
                statusText: 'NOMINAL',
                statusColor: NasaColors.capsuleGreen,
                icon: Icons.speed_rounded,
              ),
              _VitalMetricCard(
                title: 'SPINE POSTURE (C)',
                value: '224²',
                unit: 'RGB',
                statusText: 'RISK: 14%',
                statusColor: NasaColors.capsuleGreen,
                icon: Icons.accessibility_new_rounded,
              ),
              _VitalMetricCard(
                title: 'RADIATION DOSE',
                value: '0.42',
                unit: 'mSv/d',
                statusText: 'SOLAR WARN',
                statusColor: NasaColors.warningAmber,
                icon: Icons.radar_rounded,
              ),
            ],
          ),
        ],
      ),
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
              border: Border.all(color: NasaColors.biometricCyan.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CREW HEALTH ADHERENCE SCORE',
                      style: TextStyle(color: NasaColors.nebulaGrey, fontSize: 11),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8),
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
                    decoration: task.done ? TextDecoration.lineThrough : TextDecoration.none,
                  ),
                ),
                subtitle: Text(
                  '${task.hazard}  •  +${task.xp} XP',
                  style: const TextStyle(color: NasaColors.biometricCyan, fontSize: 11),
                ),
                onChanged: (bool? v) => setState(() => _missionTasks[i].done = v ?? false),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEnvironmentSelector() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _environments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final String env = _environments[index];
          final bool isSelected = env == _selectedEnvironment;
          return ChoiceChip(
            label: Text(env),
            selected: isSelected,
            onSelected: (_) => setState(() => _selectedEnvironment = env),
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

    return Container(
      height: 290,
      width: double.infinity,
      decoration: BoxDecoration(
        color: NasaColors.stationGrey,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: activeColor.withValues(alpha: 0.6), width: 1.5),
        gradient: RadialGradient(
          colors: [
            activeColor.withValues(alpha: 0.15),
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
                const Text(
                  'PERFECTUM 3D READY',
                  style: TextStyle(color: NasaColors.biometricCyan, fontSize: 10),
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? partColor.withValues(alpha: 0.25)
                          : NasaColors.darkMatter.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? partColor : NasaColors.nebulaGrey.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      partName.split(' ').first,
                      style: TextStyle(
                        color: isSelected ? NasaColors.pureWhite : NasaColors.nebulaGrey,
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

  const _VitalMetricCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.statusText,
    required this.statusColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
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
                Text(unit, style: const TextStyle(color: NasaColors.nebulaGrey, fontSize: 11)),
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}