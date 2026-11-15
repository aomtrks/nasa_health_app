import 'package:flutter/material.dart';
import 'package:nasa_health_app/core/theme/app_theme.dart';

class NasaDrawer extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  const NasaDrawer({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Drawer(
      backgroundColor: NasaColors.darkMatter,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(
              top: 52,
              bottom: 20,
              left: 20,
              right: 20,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [NasaColors.deepSpaceBlue, NasaColors.darkMatter],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border(
                bottom: BorderSide(color: NasaColors.biometricCyan, width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: NasaColors.biometricCyan,
                          width: 2,
                        ),
                      ),
                      child: const CircleAvatar(
                        radius: 24,
                        backgroundColor: NasaColors.stationGrey,
                        child: Icon(
                          Icons.person,
                          color: NasaColors.biometricCyan,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CDR. M. A. ÖZTÜRK',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: NasaColors.pureWhite,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: NasaColors.capsuleGreen.withValues(
                                alpha: 0.2,
                              ),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: NasaColors.capsuleGreen,
                                width: 0.8,
                              ),
                            ),
                            child: const Text(
                              'KERAS AI: CONNECTED',
                              style: TextStyle(
                                color: NasaColors.capsuleGreen,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _MissionBadge(label: 'MISSION', value: 'ARTEMIS IV'),
                    _MissionBadge(label: 'SOL DAY', value: 'SOL 142'),
                    _MissionBadge(label: 'MODELS', value: 'A / B / C + MLKIT'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              children: [
                _buildNavItem(
                  index: 0,
                  icon: Icons.accessibility_new_rounded,
                  title: '3D Biometric Twin',
                  subtitle: 'Interactive Body & Live Telemetry',
                ),
                _buildNavItem(
                  index: 1,
                  icon: Icons.memory_rounded,
                  title: 'AI Diagnostic Lab (.keras)',
                  subtitle: 'ECG [187], Cardio [12], Posture [224²]',
                ),
                _buildNavItem(
                  index: 2,
                  icon: Icons.task_alt_rounded,
                  title: 'Countermeasures & Guide',
                  subtitle: 'Daily Protocols & Space Hazards',
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                bottomInset > 0 ? 12 : 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NasaColors.orbitRed,
                        foregroundColor: NasaColors.pureWhite,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: NasaColors.orbitRed,
                            content: Text(
                              'EMERGENCY TELEMETRY SENT TO FLIGHT SURGEON',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.warning_amber_rounded, size: 20),
                      label: const Text(
                        'ALERT FLIGHT SURGEON',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'KERAS 3.16 FLOAT32 • OFFLINE CAPABLE',
                    style: TextStyle(
                      color: NasaColors.nebulaGrey,
                      fontSize: 10,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Space weather data: NASA CCMC DONKI\n(ccmc.gsfc.nasa.gov/DONKI)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: NasaColors.biometricCyan,
                      fontSize: 9,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final bool isSelected = selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: isSelected
            ? NasaColors.deepSpaceBlue.withValues(alpha: 0.35)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected
                ? NasaColors.biometricCyan.withValues(alpha: 0.7)
                : Colors.transparent,
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(
            icon,
            color: isSelected ? NasaColors.biometricCyan : NasaColors.nebulaGrey,
          ),
          title: Text(
            title,
            style: TextStyle(
              color: isSelected ? NasaColors.pureWhite : NasaColors.starlightWhite,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(color: NasaColors.nebulaGrey, fontSize: 11),
          ),
          onTap: () => onItemSelected(index),
        ),
      ),
    );
  }
}

class _MissionBadge extends StatelessWidget {
  final String label;
  final String value;

  const _MissionBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: NasaColors.nebulaGrey,
            fontSize: 9,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: NasaColors.biometricCyan,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}