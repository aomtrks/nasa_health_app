import 'dart:math' as m;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:perfectum_3d/perfectum_3d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:nasa_health_app/core/theme/app_theme.dart';

/// Anatomik parçanın üst verilerini ve perfectum_3d Mesh3D referansını tutan sınıf
class Anatomy3DNode {
  final String system; // 'skeleton', 'muscle', 'vessels'
  final String id; // 'skull', 'spine', 'heart', 'artery', 'vein', 'muscle', 'femur'...
  final String name;
  final Color baseColor;
  final List<vm.Vector3> baseVertices;
  final List<int> baseIndices;
  final vm.Matrix4 baseTransform;
  final vm.Vector3 center;
  final double hitRadius;

  const Anatomy3DNode({
    required this.system,
    required this.id,
    required this.name,
    required this.baseColor,
    required this.baseVertices,
    required this.baseIndices,
    required this.baseTransform,
    required this.center,
    required this.hitRadius,
  });

  /// Rengi güncellenmiş ve orijinal transform matrisi korunmuş Mesh3D döndürür
  Mesh3D toMesh3D(Color activeColor) {
    final Mesh3D m3d = Mesh3D(
      vertices: baseVertices,
      indices: baseIndices,
      color: activeColor,
    );
    m3d.transform = baseTransform.clone();
    return m3d;
  }
}

const Map<String, String> kAnatomySpaceInfo = <String, String>{
  'skull':
      'Protects the brain.|Cephalad fluid shifts in 0G raise intracranial pressure & SANS risk.|Check headache, visual acuity & facial fatigue.',
  'spine':
      'Supports trunk & shields spinal cord.|Spine lengthens up to 5 cm in microgravity; lumbar disc herniation risk.|Run Module C (224x224 Posture Scan) & resistive loading.',
  'ribs':
      'Thoracic cage protecting heart and lungs.|Microgravity alters rib-cage mechanics and tidal breathing.|Monitor SpO2 & respiratory rate.',
  'pelvis':
      'Primary load-bearing pelvic ring.|Fastest bone mineral loss site in space: ~1.0–1.5% per month.|Perform daily ARED squats & deadlifts + Vitamin D.',
  'femur':
      'Longest weight-bearing bone.|Proximal femur loses trabecular density rapidly without 1G impact.|Complete 45-min ARED resistive protocol.',
  'tibia':
      'Lower leg weight-bearing shin bone.|Unloading in 0G/Lunar gravity reduces cortical thickness.|Treadmill T2 harness running.',
  'humerus':
      'Upper arm bone.|Heavily loaded during EVA suit translation and maintenance.|Monitor shoulder & elbow joint torque.',
  'shoulder':
      'Glenohumeral ball-and-socket joint.|High injury rate inside pressurized EVA spacesuits.|Check range of motion before spacewalk.',
  'hip':
      'Femoroacetabular joint.|Critical bone density monitoring target on long Mars transits.|Resistive hip loading.',
  'knee':
      'Tibiofemoral hinge joint.|Cartilage thins during prolonged unloading; recondition gradually.|ARED squat alignment check.',
  'muscle':
      'Skeletal muscle fibers (posture & locomotion).|Up to 20% muscle mass loss in 2 weeks without resistance exercise.|Daily ARED + cycle ergometer protocol.',
  'heart':
      'Central cardiovascular pump.|Spherical remodeling in 0G & radiation-induced arrhythmia risk.|Run Module A (187-sample ECG) & Module B (Cardio).',
  'artery':
      'High-pressure oxygenated arterial network.|Space radiation accelerates arterial stiffening & endothelial stress.|Monitor Systolic/Diastolic BP (Module B).',
  'vein':
      'Venous return system.|Cephalad fluid shift causes jugular distension & thrombosis risk.|Monitor hydration & neck vein flow.',
};

class Astronaut3DViewer extends StatefulWidget {
  final String selectedBodyRegion;
  final ValueChanged<String>? onBodyRegionSelected;
  final double cardioRisk; // 0.0 .. 1.0 (Module A + B)
  final double postureRisk; // 0.0 .. 1.0 (Module C)
  final double neuroStress; // 0.0 .. 1.0 (ML Kit / Radiation)
  final int heartRateBpm;
  final String gravityLabel;

  const Astronaut3DViewer({
    super.key,
    required this.selectedBodyRegion,
    this.onBodyRegionSelected,
    required this.cardioRisk,
    required this.postureRisk,
    required this.neuroStress,
    required this.heartRateBpm,
    required this.gravityLabel,
  });

  @override
  State<Astronaut3DViewer> createState() => _Astronaut3DViewerState();
}

class _Astronaut3DViewerState extends State<Astronaut3DViewer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  // Sistem görünürlük durumları (Kemik, Kas ve Damar ayrı ayrı veya birlikte)
  bool _showSkeleton = true;
  bool _showMuscle = true;
  bool _showVessels = true;
  bool _femaleModel = false;
  bool _isolateSystem = false;

  // Orbit Kamera Açıları (Camera3D konumunu belirler)
  double _yaw = 0.28;
  double _pitch = 0.10;
  double _zoom = 1.0;
  double _gestureStartZoom = 1.0;

  Anatomy3DNode? _selectedNode;
  late List<Anatomy3DNode> _allNodes;

  @override
  void initState() {
    super.initState();
    _allNodes = _buildAnatomicalNodes(_femaleModel);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // Orbit kamerasını (Camera3D) o anki _yaw, _pitch ve _zoom değerlerine göre kurar
  Camera3D _buildCamera(Size viewportSize) {
    final double radius = 15.5 / _zoom;
    final double camX = radius * m.cos(_pitch) * m.sin(_yaw);
    final double camY = 0.4 + (radius * m.sin(_pitch));
    final double camZ = radius * m.cos(_pitch) * m.cos(_yaw);

    final double aspect = viewportSize.height > 0
        ? viewportSize.width / viewportSize.height
        : 1.0;

    return Camera3D(
      position: vm.Vector3(camX, camY, camZ),
      target: vm.Vector3(0.0, 0.3, 0.0),
      up: vm.Vector3(0.0, 1.0, 0.0),
      fovDegrees: 50.0,
      aspectRatio: aspect,
      zNear: 0.1,
      zFar: 500.0,
    );
  }

  // ---------------------------------------------------------------------------
  // PERFECTUM_3D GEOMETRY BUILDER (BoxGeometry & SphereGeometry)
  // ---------------------------------------------------------------------------
  List<Anatomy3DNode> _buildAnatomicalNodes(bool female) {
    final List<Anatomy3DNode> nodes = <Anatomy3DNode>[];
    final double scale = female ? 0.94 : 1.0;
    final double sw = (female ? 1.55 : 1.80) * scale; // Omuz genişliği
    final double hw = (female ? 0.82 : 0.72) * scale; // Kalça genişliği

    const Color boneColor = Color(0xFFE6F7FF);
    const Color jointColor = Color(0xFF80E5FF);
    const Color musclePrimary = Color(0xFFFF6A4A);
    const Color muscleSecondary = Color(0xFFD8432E);
    const Color arteryRed = Color(0xFFFF2E4C);
    const Color veinBlue = Color(0xFF2979FF);
    const Color heartCrimson = Color(0xFFFF1744);

    // Kütüphanendeki BoxGeometry kullanarak 3D parça ekler (cow.dart / tree.dart stili)
    void addBoxPart({
      required String sys,
      required String id,
      required String name,
      required Color color,
      required double w,
      required double h,
      required double d,
      required double x,
      required double y,
      required double z,
      double rx = 0,
      double ry = 0,
      double rz = 0,
    }) {
      final Mesh3D box = BoxGeometry(
        width: w * scale,
        height: h * scale,
        depth: d * scale,
        color: color,
      ).translate(x: x * scale, y: y * scale, z: z * scale);

      if (rx != 0) box.rotateX(rx);
      if (ry != 0) box.rotateY(ry);
      if (rz != 0) box.rotateZ(rz);

      nodes.add(
        Anatomy3DNode(
          system: sys,
          id: id,
          name: name,
          baseColor: color,
          baseVertices: box.vertices,
          baseIndices: box.indices,
          baseTransform: box.transform.clone(),
          center: vm.Vector3(x * scale, y * scale, z * scale),
          hitRadius: m.max(w, m.max(h, d)) * 0.65 * scale,
        ),
      );
    }

    // Kütüphanendeki SphereGeometry({radius, segments, color}) kullanarak küre ekler
    void addSpherePart({
      required String sys,
      required String id,
      required String name,
      required Color color,
      required double radius,
      required double x,
      required double y,
      required double z,
      int segments = 10,
    }) {
      final Mesh3D sphere = SphereGeometry(
        radius: radius * scale,
        segments: segments,
        color: color,
      ).translate(x: x * scale, y: y * scale, z: z * scale);

      nodes.add(
        Anatomy3DNode(
          system: sys,
          id: id,
          name: name,
          baseColor: color,
          baseVertices: sphere.vertices,
          baseIndices: sphere.indices,
          baseTransform: sphere.transform.clone(),
          center: vm.Vector3(x * scale, y * scale, z * scale),
          hitRadius: radius * 1.45 * scale,
        ),
      );
    }

    // İki 3D nokta arasına yönlendirilmiş kemik, kas veya damar segmenti ekler
    void addSegmentBar({
      required String sys,
      required String id,
      required String name,
      required Color color,
      required List<double> p1,
      required List<double> p2,
      required double thickness,
    }) {
      final double dx = p2[0] - p1[0];
      final double dy = p2[1] - p1[1];
      final double dz = p2[2] - p1[2];
      final double len = m.sqrt(dx * dx + dy * dy + dz * dz);
      if (len < 0.001) return;

      final double cx = (p1[0] + p2[0]) * 0.5;
      final double cy = (p1[1] + p2[1]) * 0.5;
      final double cz = (p1[2] + p2[2]) * 0.5;

      final double rz = -m.atan2(dx, dy);
      final double rx = m.atan2(dz, m.sqrt(dx * dx + dy * dy));

      // Önce translate, sonra rotate (cow.dart / tree.dart ile aynı Matrix4 sırası)
      final Mesh3D bar = BoxGeometry(
        width: thickness * 1.75 * scale,
        height: len * scale,
        depth: thickness * 1.75 * scale,
        color: color,
      ).translate(x: cx * scale, y: cy * scale, z: cz * scale);

      if (rz.abs() > 0.01) bar.rotateZ(rz);
      if (rx.abs() > 0.01) bar.rotateX(rx);

      nodes.add(
        Anatomy3DNode(
          system: sys,
          id: id,
          name: name,
          baseColor: color,
          baseVertices: bar.vertices,
          baseIndices: bar.indices,
          baseTransform: bar.transform.clone(),
          center: vm.Vector3(cx * scale, cy * scale, cz * scale),
          hitRadius: m.max(len * 0.45, thickness * 2.2) * scale,
        ),
      );
    }

    // =========================================================================
    // 1. SKELETAL SYSTEM (KEMİK VE EKLEM SİSTEMİ)
    // =========================================================================
    // Kafatası (Cranium SphereGeometry & Mandible BoxGeometry)
    addSpherePart(
      sys: 'skeleton',
      id: 'skull',
      name: 'Cranium (Skull)',
      color: boneColor,
      radius: 0.90,
      x: 0,
      y: 6.45,
      z: -0.05,
      segments: 12,
    );
    addBoxPart(
      sys: 'skeleton',
      id: 'skull',
      name: 'Mandible (Jaw Bone)',
      color: boneColor,
      w: 0.95,
      h: 0.52,
      d: 0.85,
      x: 0,
      y: 5.65,
      z: 0.22,
    );

    // Omurga Sütunu (Cervical C1-C7, Thoracic T1-T12, Lumbar L1-L5)
    for (int i = 0; i < 18; i++) {
      final double y = 5.25 - (i * 0.28);
      final double zCurve = -0.45 + 0.18 * m.cos((i / 17.0) * m.pi * 2.5);
      final double w = 0.34 + (i * 0.012);
      final String vLabel = i < 5
          ? 'Cervical Vertebra C${i + 1}'
          : (i < 13
              ? 'Thoracic Vertebra T${i - 4}'
              : 'Lumbar Vertebra L${i - 12}');
      addBoxPart(
        sys: 'skeleton',
        id: 'spine',
        name: vLabel,
        color: boneColor,
        w: w,
        h: 0.20,
        d: 0.32,
        x: 0,
        y: y,
        z: zCurve,
      );
    }

    // Sternum (Göğüs Kemiği)
    addBoxPart(
      sys: 'skeleton',
      id: 'ribs',
      name: 'Sternum (Breastbone)',
      color: boneColor,
      w: 0.32,
      h: 1.65,
      d: 0.18,
      x: 0,
      y: 3.65,
      z: 0.82,
    );

    // Pelvis (Sacrum & Pelvic Ring)
    addBoxPart(
      sys: 'skeleton',
      id: 'pelvis',
      name: 'Sacrum & Pelvic Ring',
      color: boneColor,
      w: hw * 2.1,
      h: 0.85,
      d: 0.75,
      x: 0,
      y: 0.25,
      z: -0.10,
    );

    // Sağ ve Sol Simetrik İskelet, Kas ve Damar Yapıları
    for (final double s in <double>[-1.0, 1.0]) {
      final String side = s < 0 ? 'Right ' : 'Left ';

      // Kaburgalar (Rib Cage - 8 Çift)
      for (int r = 0; r < 8; r++) {
        final double ry = 4.45 - (r * 0.26);
        final double span = (0.85 + (r < 5 ? r * 0.11 : (7 - r) * 0.12));
        addBoxPart(
          sys: 'skeleton',
          id: 'ribs',
          name: '${side}Rib ${r + 1}',
          color: boneColor,
          w: span,
          h: 0.11,
          d: 0.95,
          x: s * (span * 0.52),
          y: ry,
          z: 0.15,
        );
      }

      // Köprücük Kemiği (Clavicle) & Kürek Kemiği (Scapula)
      addSegmentBar(
        sys: 'skeleton',
        id: 'shoulder',
        name: '${side}Clavicle (Collarbone)',
        color: boneColor,
        p1: <double>[s * 0.20, 4.65, 0.45],
        p2: <double>[s * sw, 4.55, 0.0],
        thickness: 0.11,
      );
      addBoxPart(
        sys: 'skeleton',
        id: 'shoulder',
        name: '${side}Scapula (Shoulder Blade)',
        color: boneColor,
        w: 0.75,
        h: 0.95,
        d: 0.14,
        x: s * (sw * 0.65),
        y: 3.95,
        z: -0.58,
      );

      // Kol Koordinatları
      final List<double> sh = <double>[s * sw, 4.45, 0.0];
      final List<double> el = <double>[s * (sw + 0.35), 2.15, 0.05];
      final List<double> wr = <double>[s * (sw + 0.65), 0.15, 0.25];

      // Bacak Koordinatları
      final List<double> hp = <double>[s * hw, -0.15, 0.0];
      final List<double> kn = <double>[s * (hw + 0.08), -3.25, 0.08];
      final List<double> an = <double>[s * (hw + 0.12), -6.25, 0.0];

      // Eklemler (SphereGeometry Joint Spheres)
      addSpherePart(
        sys: 'skeleton',
        id: 'shoulder',
        name: '${side}Shoulder Joint',
        color: jointColor,
        radius: 0.28,
        x: sh[0],
        y: sh[1],
        z: sh[2],
        segments: 8,
      );
      addSpherePart(
        sys: 'skeleton',
        id: 'humerus',
        name: '${side}Elbow Joint',
        color: jointColor,
        radius: 0.22,
        x: el[0],
        y: el[1],
        z: el[2],
        segments: 8,
      );
      addSpherePart(
        sys: 'skeleton',
        id: 'hip',
        name: '${side}Hip Joint',
        color: jointColor,
        radius: 0.32,
        x: hp[0],
        y: hp[1],
        z: hp[2],
        segments: 8,
      );
      addSpherePart(
        sys: 'skeleton',
        id: 'knee',
        name: '${side}Knee Joint',
        color: jointColor,
        radius: 0.28,
        x: kn[0],
        y: kn[1],
        z: kn[2],
        segments: 8,
      );

      // Kol Kemikleri (Humerus, Radius & Ulna, Hand Phalanges)
      addSegmentBar(
        sys: 'skeleton',
        id: 'humerus',
        name: '${side}Humerus',
        color: boneColor,
        p1: sh,
        p2: el,
        thickness: 0.17,
      );
      addSegmentBar(
        sys: 'skeleton',
        id: 'humerus',
        name: '${side}Radius & Ulna',
        color: boneColor,
        p1: el,
        p2: wr,
        thickness: 0.13,
      );
      addBoxPart(
        sys: 'skeleton',
        id: 'humerus',
        name: '${side}Metacarpals & Phalanges (Hand)',
        color: boneColor,
        w: 0.28,
        h: 0.65,
        d: 0.16,
        x: wr[0] + (s * 0.05),
        y: wr[1] - 0.42,
        z: wr[2] + 0.05,
      );

      // Bacak Kemikleri (Femur, Tibia, Fibula, Foot Tarsals)
      addSegmentBar(
        sys: 'skeleton',
        id: 'femur',
        name: '${side}Femur (Thigh Bone)',
        color: boneColor,
        p1: hp,
        p2: kn,
        thickness: 0.23,
      );
      addSegmentBar(
        sys: 'skeleton',
        id: 'tibia',
        name: '${side}Tibia (Shin Bone)',
        color: boneColor,
        p1: kn,
        p2: an,
        thickness: 0.19,
      );
      addSegmentBar(
        sys: 'skeleton',
        id: 'tibia',
        name: '${side}Fibula',
        color: boneColor,
        p1: <double>[kn[0] + s * 0.16, kn[1] - 0.1, kn[2] - 0.05],
        p2: <double>[an[0] + s * 0.16, an[1], an[2] - 0.05],
        thickness: 0.09,
      );
      addBoxPart(
        sys: 'skeleton',
        id: 'tibia',
        name: '${side}Foot Tarsals & Metatarsals',
        color: boneColor,
        w: 0.42,
        h: 0.26,
        d: 0.95,
        x: an[0],
        y: an[1] - 0.18,
        z: an[2] + 0.32,
      );

      // =======================================================================
      // 2. MUSCULAR SYSTEM (KAS SİSTEMİ)
      // =======================================================================
      // Göğüs Kasları (Pectoralis Major)
      addBoxPart(
        sys: 'muscle',
        id: 'muscle',
        name: '${side}Pectoralis Major',
        color: musclePrimary,
        w: 1.05,
        h: 0.92,
        d: 0.42,
        x: s * 0.62,
        y: 3.82,
        z: 0.68,
      );

      // Omuz Kasları (Deltoid SphereGeometry)
      addSpherePart(
        sys: 'muscle',
        id: 'muscle',
        name: '${side}Deltoid Muscle',
        color: muscleSecondary,
        radius: 0.44,
        x: sh[0] + (s * 0.08),
        y: sh[1] - 0.05,
        z: 0.08,
        segments: 10,
      );

      // Kol Kasları (Biceps Brachii, Triceps Brachii, Forearm Flexors)
      addSegmentBar(
        sys: 'muscle',
        id: 'muscle',
        name: '${side}Biceps Brachii',
        color: musclePrimary,
        p1: <double>[sh[0], sh[1] - 0.2, sh[2] + 0.22],
        p2: <double>[el[0], el[1] + 0.2, el[2] + 0.20],
        thickness: 0.24,
      );
      addSegmentBar(
        sys: 'muscle',
        id: 'muscle',
        name: '${side}Triceps Brachii',
        color: muscleSecondary,
        p1: <double>[sh[0], sh[1] - 0.2, sh[2] - 0.20],
        p2: <double>[el[0], el[1] + 0.2, el[2] - 0.18],
        thickness: 0.22,
      );
      addSegmentBar(
        sys: 'muscle',
        id: 'muscle',
        name: '${side}Brachioradialis & Forearm Flexors',
        color: musclePrimary,
        p1: <double>[el[0], el[1], el[2] + 0.08],
        p2: <double>[wr[0], wr[1] + 0.25, wr[2] + 0.08],
        thickness: 0.18,
      );

      // Karın Kasları (Rectus Abdominis & External Oblique)
      for (int ab = 0; ab < 3; ab++) {
        addBoxPart(
          sys: 'muscle',
          id: 'muscle',
          name: '${side}Rectus Abdominis Segment ${ab + 1}',
          color: musclePrimary,
          w: 0.44,
          h: 0.48,
          d: 0.24,
          x: s * 0.28,
          y: 2.65 - (ab * 0.62),
          z: 0.78,
        );
      }
      addBoxPart(
        sys: 'muscle',
        id: 'muscle',
        name: '${side}External Oblique & Latissimus Dorsi',
        color: muscleSecondary,
        w: 0.42,
        h: 1.85,
        d: 0.85,
        x: s * 0.92,
        y: 2.25,
        z: 0.05,
      );

      // Kalça ve Bacak Kasları (Gluteus, Quadriceps, Hamstrings, Gastrocnemius)
      addSpherePart(
        sys: 'muscle',
        id: 'muscle',
        name: '${side}Gluteus Maximus',
        color: muscleSecondary,
        radius: 0.52,
        x: s * 0.65,
        y: -0.10,
        z: -0.52,
        segments: 10,
      );
      addSegmentBar(
        sys: 'muscle',
        id: 'muscle',
        name: '${side}Quadriceps (Rectus Femoris & Vastus)',
        color: musclePrimary,
        p1: <double>[hp[0], hp[1] - 0.15, hp[2] + 0.28],
        p2: <double>[kn[0], kn[1] + 0.25, kn[2] + 0.24],
        thickness: 0.30,
      );
      addSegmentBar(
        sys: 'muscle',
        id: 'muscle',
        name: '${side}Hamstrings (Biceps Femoris)',
        color: muscleSecondary,
        p1: <double>[hp[0], hp[1] - 0.15, hp[2] - 0.26],
        p2: <double>[kn[0], kn[1] + 0.25, kn[2] - 0.22],
        thickness: 0.28,
      );
      addSegmentBar(
        sys: 'muscle',
        id: 'muscle',
        name: '${side}Gastrocnemius & Soleus (Calf)',
        color: musclePrimary,
        p1: <double>[kn[0], kn[1] - 0.20, kn[2] - 0.20],
        p2: <double>[an[0], an[1] + 0.35, an[2] - 0.14],
        thickness: 0.24,
      );

      // =======================================================================
      // 3. VASCULAR SYSTEM (DAMAR SİSTEMİ - ARTERLER VE VENLER)
      // =======================================================================
      // Şah Damarı ve Jugular Ven (Carotid Artery & Internal Jugular Vein)
      addSegmentBar(
        sys: 'vessels',
        id: 'artery',
        name: '${side}Common Carotid Artery',
        color: arteryRed,
        p1: <double>[s * 0.22, 4.10, 0.25],
        p2: <double>[s * 0.30, 6.10, 0.18],
        thickness: 0.08,
      );
      addSegmentBar(
        sys: 'vessels',
        id: 'vein',
        name: '${side}Internal Jugular Vein',
        color: veinBlue,
        p1: <double>[s * 0.34, 4.05, 0.15],
        p2: <double>[s * 0.38, 6.05, 0.08],
        thickness: 0.08,
      );

      // Kol Arter ve Venleri (Subclavian -> Brachial -> Radial/Ulnar)
      addSegmentBar(
        sys: 'vessels',
        id: 'artery',
        name: '${side}Subclavian & Brachial Artery',
        color: arteryRed,
        p1: <double>[0.0, 4.15, 0.32],
        p2: <double>[el[0] - s * 0.08, el[1], el[2] + 0.12],
        thickness: 0.075,
      );
      addSegmentBar(
        sys: 'vessels',
        id: 'artery',
        name: '${side}Radial & Ulnar Artery',
        color: arteryRed,
        p1: <double>[el[0] - s * 0.08, el[1], el[2] + 0.12],
        p2: <double>[wr[0] - s * 0.06, wr[1], wr[2] + 0.10],
        thickness: 0.065,
      );
      addSegmentBar(
        sys: 'vessels',
        id: 'vein',
        name: '${side}Cephalic & Basilic Arm Vein',
        color: veinBlue,
        p1: <double>[wr[0] + s * 0.08, wr[1], wr[2] - 0.05],
        p2: <double>[sh[0] * 0.6, 3.95, 0.18],
        thickness: 0.075,
      );

      // Bacak Arter ve Venleri (Iliac -> Femoral -> Tibial)
      addSegmentBar(
        sys: 'vessels',
        id: 'artery',
        name: '${side}Iliac & Femoral Artery',
        color: arteryRed,
        p1: <double>[0.0, 0.55, 0.15],
        p2: <double>[kn[0] - s * 0.08, kn[1], kn[2] + 0.10],
        thickness: 0.095,
      );
      addSegmentBar(
        sys: 'vessels',
        id: 'artery',
        name: '${side}Anterior Tibial Artery',
        color: arteryRed,
        p1: <double>[kn[0] - s * 0.08, kn[1], kn[2] + 0.10],
        p2: <double>[an[0] - s * 0.06, an[1], an[2] + 0.10],
        thickness: 0.075,
      );
      addSegmentBar(
        sys: 'vessels',
        id: 'vein',
        name: '${side}Great Saphenous & Femoral Vein',
        color: veinBlue,
        p1: <double>[an[0] + s * 0.08, an[1], an[2] - 0.05],
        p2: <double>[-0.18, 0.60, 0.08],
        thickness: 0.095,
      );
    }

    // Merkez Kalp (SphereGeometry), Aorta ve Vena Cava
    addSpherePart(
      sys: 'vessels',
      id: 'heart',
      name: 'Heart (Myocardium & Ventricles)',
      color: heartCrimson,
      radius: 0.54,
      x: 0.25,
      y: 3.55,
      z: 0.45,
      segments: 12,
    );
    addSegmentBar(
      sys: 'vessels',
      id: 'artery',
      name: 'Ascending Aorta & Abdominal Aorta',
      color: arteryRed,
      p1: <double>[0.18, 4.25, 0.30],
      p2: <double>[0.05, 0.55, 0.15],
      thickness: 0.13,
    );
    addSegmentBar(
      sys: 'vessels',
      id: 'vein',
      name: 'Superior & Inferior Vena Cava',
      color: veinBlue,
      p1: <double>[-0.22, 4.30, 0.20],
      p2: <double>[-0.18, 0.60, 0.08],
      thickness: 0.13,
    );

    return nodes;
  }

  List<Anatomy3DNode> get _visibleNodes {
    return _allNodes.where((Anatomy3DNode node) {
      if (_isolateSystem && _selectedNode != null) {
        return node.system == _selectedNode!.system;
      }
      if (node.system == 'skeleton' && !_showSkeleton) return false;
      if (node.system == 'muscle' && !_showMuscle) return false;
      if (node.system == 'vessels' && !_showVessels) return false;
      return true;
    }).toList(growable: false);
  }

  // AI Model risklerine ve seçime göre her 3D parçanın rengini hesaplar
  Color _resolveNodeColor(Anatomy3DNode node, double pulseValue) {
    if (identical(node, _selectedNode)) {
      return const Color(0xFFFFEA00); // Seçili parça parlak altın sarısı
    }

    Color c = node.baseColor;

    // 1. Kalp & Damar: Module A (ECG) + Module B (Cardio) riskine duyarlı
    if (node.id == 'heart') {
      if (widget.cardioRisk > 0.40) {
        c = Color.lerp(NasaColors.orbitRed, Colors.white, 0.45 * pulseValue)!;
      } else {
        c = Color.lerp(
          node.baseColor,
          const Color(0xFFFF8A80),
          0.25 * pulseValue,
        )!;
      }
    } else if (node.system == 'vessels' && widget.cardioRisk > 0.45) {
      c = Color.lerp(c, NasaColors.orbitRed, 0.45 * pulseValue)!;
    }

    // 2. Omurga & Kemik: Module C (Posture) riskine duyarlı
    if (node.id == 'spine' && widget.postureRisk > 0.40) {
      c = Color.lerp(
        node.baseColor,
        NasaColors.warningAmber,
        0.65 + 0.25 * pulseValue,
      )!;
    }

    // 3. Kafatası: Radyasyon / Nörolojik strese duyarlı
    if (node.id == 'skull' && widget.neuroStress > 0.45) {
      c = Color.lerp(node.baseColor, NasaColors.orbitRed, 0.55)!;
    }

    return c;
  }

  // Camera3D.projectToClipSpace() kullanarak tıklanan kemik/kas/damarı bulur
  void _handleCanvasTap(Offset localTap, Size viewSize) {
    if (viewSize.width <= 0 || viewSize.height <= 0) return;
    final Camera3D cam = _buildCamera(viewSize);
    final List<Anatomy3DNode> active = _visibleNodes;

    Anatomy3DNode? bestMatch;
    double bestDist = double.infinity;

    for (final Anatomy3DNode node in active) {
      final vm.Vector4 clip = cam.projectToClipSpace(node.center);
      if (clip.w <= 0.1) continue;

      final double ndcX = clip.x / clip.w;
      final double ndcY = clip.y / clip.w;

      final double sx = (ndcX + 1.0) * 0.5 * viewSize.width;
      final double sy = (1.0 - ndcY) * 0.5 * viewSize.height;

      final double hitPx =
          (node.hitRadius * viewSize.height / clip.w).clamp(18.0, 48.0);
      final double dist = (Offset(sx, sy) - localTap).distance;

      if (dist <= hitPx && dist < bestDist) {
        bestDist = dist;
        bestMatch = node;
      }
    }

    if (bestMatch != null) {
      setState(() => _selectedNode = bestMatch);
      if (bestMatch.id == 'skull') {
        widget.onBodyRegionSelected?.call('Neurological (Head)');
      } else if (bestMatch.system == 'vessels' || bestMatch.id == 'heart') {
        widget.onBodyRegionSelected?.call('Cardiovascular (Heart)');
      } else {
        widget.onBodyRegionSelected?.call('Musculoskeletal (Spine)');
      }
    }
  }

  void _applySystemPreset(String mode) {
    setState(() {
      if (mode == 'skeleton') {
        _showSkeleton = true;
        _showMuscle = false;
        _showVessels = false;
      } else if (mode == 'muscle') {
        _showSkeleton = false;
        _showMuscle = true;
        _showVessels = false;
      } else if (mode == 'vessels') {
        _showSkeleton = false;
        _showMuscle = false;
        _showVessels = true;
      } else {
        _showSkeleton = true;
        _showMuscle = true;
        _showVessels = true;
      }
      _isolateSystem = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NasaColors.stationGrey,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: NasaColors.biometricCyan.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. ÜST BAR: Başlık, Cinsiyet Seçimi ve Kamera Sıfırlama
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PERFECTUM 3D • HOLOGRAPHIC ANATOMY',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: NasaColors.biometricCyan,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.9,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.gravityLabel} • HR: ${widget.heartRateBpm} BPM',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: NasaColors.nebulaGrey,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    _buildSmallActionBtn(
                      label: _femaleModel ? 'FEMALE' : 'MALE',
                      icon: Icons.person_outline,
                      onTap: () {
                        setState(() {
                          _femaleModel = !_femaleModel;
                          _allNodes = _buildAnatomicalNodes(_femaleModel);
                          _selectedNode = null;
                        });
                      },
                    ),
                    const SizedBox(width: 6),
                    _buildSmallActionBtn(
                      label: 'RESET',
                      icon: Icons.center_focus_strong,
                      onTap: () {
                        setState(() {
                          _yaw = 0.28;
                          _pitch = 0.10;
                          _zoom = 1.0;
                          _selectedNode = null;
                          _isolateSystem = false;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. SİSTEM FİLTRELERİ (KEMİK / KAS / DAMAR AYRI AYRI VEYA BİRLİKTE)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildSystemFilterChip(
                    label: 'SKELETAL (BONE)',
                    active: _showSkeleton,
                    activeColor: const Color(0xFF80E5FF),
                    icon: Icons.accessibility_new_rounded,
                    onSelected: (bool v) => setState(() => _showSkeleton = v),
                    onDoubleTap: () => _applySystemPreset('skeleton'),
                  ),
                  const SizedBox(width: 6),
                  _buildSystemFilterChip(
                    label: 'MUSCULAR',
                    active: _showMuscle,
                    activeColor: const Color(0xFFFF6A4A),
                    icon: Icons.fitness_center_rounded,
                    onSelected: (bool v) => setState(() => _showMuscle = v),
                    onDoubleTap: () => _applySystemPreset('muscle'),
                  ),
                  const SizedBox(width: 6),
                  _buildSystemFilterChip(
                    label: 'VASCULAR (VESSELS)',
                    active: _showVessels,
                    activeColor: const Color(0xFFFF2E4C),
                    icon: Icons.favorite_rounded,
                    onSelected: (bool v) => setState(() => _showVessels = v),
                    onDoubleTap: () => _applySystemPreset('vessels'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Hızlı Görünüm Modları (Only Bone, Only Muscle, Only Vessels, All)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildPresetButton(
                  'Only Bone',
                  () => _applySystemPreset('skeleton'),
                ),
                _buildPresetButton(
                  'Only Muscle',
                  () => _applySystemPreset('muscle'),
                ),
                _buildPresetButton(
                  'Only Vessels',
                  () => _applySystemPreset('vessels'),
                ),
                _buildPresetButton(
                  'All 3 Systems',
                  () => _applySystemPreset('all'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // 3. PERFECTUM_3D SAHNESİ (Scene3D: camera, meshes, lightDirection, backgroundColor, enableFog)
          SizedBox(
            height: 330,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Size viewportSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return Stack(
                  children: [
                    // Perfectum 3D Render Katmanı
                    Listener(
                      onPointerSignal: (PointerSignalEvent event) {
                        if (event is PointerScrollEvent) {
                          setState(() {
                            final double factor =
                                m.exp(-event.scrollDelta.dy * 0.0015);
                            _zoom = (_zoom * factor).clamp(0.55, 2.6);
                          });
                        }
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: (_) => _gestureStartZoom = _zoom,
                        onScaleUpdate: (ScaleUpdateDetails d) {
                          setState(() {
                            if (d.pointerCount > 1) {
                              _zoom = (_gestureStartZoom * d.scale)
                                  .clamp(0.55, 2.6);
                            } else {
                              _yaw -= d.focalPointDelta.dx * 0.012;
                              _pitch = (_pitch + d.focalPointDelta.dy * 0.012)
                                  .clamp(-1.25, 1.25);
                            }
                          });
                        },
                        onTapUp: (TapUpDetails d) =>
                            _handleCanvasTap(d.localPosition, viewportSize),
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (BuildContext context, _) {
                            final Camera3D camera = _buildCamera(viewportSize);
                            final List<Anatomy3DNode> activeNodes =
                                _visibleNodes;

                            final List<Mesh3D> renderedMeshes = activeNodes
                                .map(
                                  (Anatomy3DNode n) => n.toMesh3D(
                                    _resolveNodeColor(n, _pulseController.value),
                                  ),
                                )
                                .toList(growable: false);

                            final vm.Vector3 lightDir = camera.position.clone()
                              ..normalize();

                            return Scene3D(
                              camera: camera,
                              meshes: renderedMeshes,
                              lightDirection: lightDir,
                              backgroundColor: NasaColors.darkMatter,
                              enableFog: false,
                            );
                          },
                        ),
                      ),
                    ),

                    // Sol Kamera Açı Butonları (Front / Left / Right / Back)
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildCamAngleBtn('FRONT', 0.0),
                          const SizedBox(height: 4),
                          _buildCamAngleBtn('LEFT', -m.pi / 2),
                          const SizedBox(height: 4),
                          _buildCamAngleBtn('RIGHT', m.pi / 2),
                          const SizedBox(height: 4),
                          _buildCamAngleBtn('BACK', m.pi),
                        ],
                      ),
                    ),

                    // Sağ Üst Lejant (Arter / Ven / Kemik / Kas Renk Göstergesi)
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: NasaColors.darkMatter.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: NasaColors.nebulaGrey.withValues(alpha: 0.25),
                          ),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _LegendDot(
                              color: Color(0xFFE6F7FF),
                              label: 'Bone / Joint',
                            ),
                            SizedBox(height: 3),
                            _LegendDot(
                              color: Color(0xFFFF6A4A),
                              label: 'Skeletal Muscle',
                            ),
                            SizedBox(height: 3),
                            _LegendDot(
                              color: Color(0xFFFF2E4C),
                              label: 'Artery / Heart',
                            ),
                            SizedBox(height: 3),
                            _LegendDot(
                              color: Color(0xFF2979FF),
                              label: 'Venous Return',
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Seçilen Anatomik Yapı Bilgi Kartı (Tıklandığında Açılır)
                    if (_selectedNode != null)
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 8,
                        child: _buildSelectedNodePopup(_selectedNode!),
                      ),
                  ],
                );
              },
            ),
          ),

          // 4. ALT KONTROLLER: Zoom Slider ve 3 Ana Hedef Bölge Seçici
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.zoom_out_rounded,
                      size: 16,
                      color: NasaColors.nebulaGrey,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'CAMERA ZOOM',
                      style: TextStyle(
                        color: NasaColors.nebulaGrey,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: _zoom.clamp(0.55, 2.6),
                        min: 0.55,
                        max: 2.6,
                        activeColor: NasaColors.biometricCyan,
                        inactiveColor: NasaColors.darkMatter,
                        onChanged: (double v) => setState(() => _zoom = v),
                      ),
                    ),
                    const Icon(
                      Icons.zoom_in_rounded,
                      size: 16,
                      color: NasaColors.nebulaGrey,
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <String>[
                    'Neurological (Head)',
                    'Cardiovascular (Heart)',
                    'Musculoskeletal (Spine)',
                  ].map((String region) {
                    final bool isSelected = widget.selectedBodyRegion == region;
                    return GestureDetector(
                      onTap: () {
                        widget.onBodyRegionSelected?.call(region);
                        if (region.contains('Cardiovascular')) {
                          _applySystemPreset('vessels');
                        } else if (region.contains('Musculoskeletal')) {
                          setState(() {
                            _showSkeleton = true;
                            _showMuscle = true;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? NasaColors.deepSpaceBlue.withValues(alpha: 0.65)
                              : NasaColors.darkMatter.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? NasaColors.biometricCyan
                                : NasaColors.nebulaGrey.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          region.split(' ').first,
                          style: TextStyle(
                            color: isSelected
                                ? NasaColors.pureWhite
                                : NasaColors.nebulaGrey,
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemFilterChip({
    required String label,
    required bool active,
    required Color activeColor,
    required IconData icon,
    required ValueChanged<bool> onSelected,
    required VoidCallback onDoubleTap,
  }) {
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      child: FilterChip(
        avatar: Icon(
          icon,
          size: 14,
          color: active ? activeColor : NasaColors.nebulaGrey,
        ),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? NasaColors.pureWhite : NasaColors.nebulaGrey,
          ),
        ),
        selected: active,
        showCheckmark: false,
        selectedColor: NasaColors.deepSpaceBlue.withValues(alpha: 0.6),
        backgroundColor: NasaColors.darkMatter,
        side: BorderSide(
          color: active
              ? activeColor
              : NasaColors.nebulaGrey.withValues(alpha: 0.3),
        ),
        visualDensity: VisualDensity.compact,
        onSelected: onSelected,
      ),
    );
  }

  Widget _buildPresetButton(String title, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: NasaColors.darkMatter.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: NasaColors.biometricCyan.withValues(alpha: 0.25),
          ),
        ),
        child: Text(
          title,
          style: const TextStyle(
            color: NasaColors.biometricCyan,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildCamAngleBtn(String label, double targetYaw) {
    return GestureDetector(
      onTap: () => setState(() {
        _yaw = targetYaw;
        _pitch = 0.08;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: NasaColors.darkMatter.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: NasaColors.biometricCyan.withValues(alpha: 0.35),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: NasaColors.starlightWhite,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildSmallActionBtn({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: NasaColors.darkMatter,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: NasaColors.biometricCyan.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 12, color: NasaColors.biometricCyan),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: NasaColors.pureWhite,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedNodePopup(Anatomy3DNode node) {
    final String rawInfo =
        kAnatomySpaceInfo[node.id] ??
        'Anatomical structure.|Affected by microgravity and radiation.|Monitor crew telemetry.';
    final List<String> parts = rawInfo.split('|');

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: NasaColors.darkMatter.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NasaColors.biometricCyan, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.hub_rounded,
                color: NasaColors.biometricCyan,
                size: 15,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${node.name.toUpperCase()} (${node.system.toUpperCase()})',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: NasaColors.biometricCyan,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 22),
                ),
                onPressed: () =>
                    setState(() => _isolateSystem = !_isolateSystem),
                child: Text(
                  _isolateSystem ? 'SHOW ALL' : 'ISOLATE SYS',
                  style: const TextStyle(
                    color: NasaColors.capsuleGreen,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() {
                  _selectedNode = null;
                  _isolateSystem = false;
                }),
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: NasaColors.nebulaGrey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (parts.isNotEmpty)
            Text(
              parts[0],
              style: const TextStyle(color: NasaColors.pureWhite, fontSize: 11),
            ),
          if (parts.length > 1)
            Text(
              'Spaceflight Impact: ${parts[1]}',
              style: const TextStyle(
                color: NasaColors.warningAmber,
                fontSize: 10,
              ),
            ),
          if (parts.length > 2)
            Text(
              'Protocol: ${parts[2]}',
              style: const TextStyle(
                color: NasaColors.capsuleGreen,
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(color: NasaColors.starlightWhite, fontSize: 9),
        ),
      ],
    );
  }
}