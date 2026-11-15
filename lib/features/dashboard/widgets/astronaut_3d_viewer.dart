import 'dart:math' as m;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:perfectum_3d/perfectum_3d.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:nasa_health_app/core/theme/app_theme.dart';

class Anatomy3DNode {
  final String system; // 'skin', 'skeleton', 'muscle', 'vessels'
  final String id; // 'skin', 'eye', 'skull', 'spine', 'heart', 'artery', 'vein', 'muscle', 'femur'...
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
  'skin':
      'Dermal barrier, facial features, thermoregulation & tactile sensing.|Low humidity in spacecraft causes skin dryness, thinning & delayed wound healing; cosmic radiation increases cellular damage.|Monitor skin hydration, temperature & radiation dosimetry.',
  'eye':
      'Ocular globe, cornea, lens & optic nerve head.|Cephalad fluid shift in microgravity flattens the posterior globe and swells the optic disc (SANS - Spaceflight-Associated Neuro-ocular Syndrome).|Perform regular Amsler grid, visual acuity & fundus checks.',
  'skull':
      'Protects the brain and sensory organs.|Cephalad fluid shifts in 0G raise intracranial pressure & SANS risk.|Check headache, visual acuity & facial fatigue.',
  'spine':
      'Supports trunk & shields spinal cord.|Spine lengthens up to 5 cm in microgravity; high lumbar disc herniation & kyphosis risk.|Run Module C (224x224 Posture Scan) & resistive loading.',
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
  final int systolicBp;
  final int diastolicBp;
  final double radiationMsv;
  final String gravityLabel;

  const Astronaut3DViewer({
    super.key,
    required this.selectedBodyRegion,
    this.onBodyRegionSelected,
    required this.cardioRisk,
    required this.postureRisk,
    required this.neuroStress,
    required this.heartRateBpm,
    this.systolicBp = 120,
    this.diastolicBp = 80,
    this.radiationMsv = 0.42,
    required this.gravityLabel,
  });

  @override
  State<Astronaut3DViewer> createState() => _Astronaut3DViewerState();
}

class _Astronaut3DViewerState extends State<Astronaut3DViewer>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _scanController;

  // Sistem görünürlükleri (Açık mavi deri, kemik, kas, damar)
  bool _showSkin = true;
  bool _showSkeleton = true;
  bool _showMuscle = true;
  bool _showVessels = true;
  bool _femaleModel = false;
  bool _isolateSystem = false;

  // Orbit Kamera ve Odak Noktası
  double _yaw = 0.25;
  double _pitch = 0.06;
  double _zoom = 1.0;
  double _gestureStartZoom = 1.0;
  vm.Vector3 _focusTarget = vm.Vector3(0.0, 0.25, 0.0);

  // Sol üstteki 2B insan figüründe seçili olan bölge ('head', 'chest', 'core', 'left_arm', 'right_arm', 'legs')
  String? _active2DFigureZone;

  Anatomy3DNode? _selectedNode;
  late List<Anatomy3DNode> _allNodes;

  // Parlak Turuncu Uyarı Rengi ve Parlak Sarı Seçim Rengi
  static const Color _brightOrangeAlert = Color(0xFFFF6D00);
  static const Color _brightOrangeGlow = Color(0xFFFFAB00);
  static const Color _selectedYellow = Color(0xFFFFEA00);
  static const Color _lightBlueSkin = Color(0xFF7CE8FF);
  static const Color _skinFeatureCyan = Color(0xFF4DD0E1);

  @override
  void initState() {
    super.initState();
    _allNodes = _buildAnatomicalNodes(_femaleModel);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanController.dispose();
    super.dispose();
  }

  // Risk kontrol yardımcıları
  bool get _hasCardioRisk =>
      widget.cardioRisk > 0.35 ||
      widget.heartRateBpm > 100 ||
      widget.heartRateBpm < 58 ||
      widget.systolicBp > 135 ||
      widget.diastolicBp > 88;

  bool get _hasPostureRisk => widget.postureRisk > 0.35;

  bool get _hasNeuroOrRadiationRisk =>
      widget.neuroStress > 0.40 || widget.radiationMsv > 0.80;

  bool _isNodeAtRisk(Anatomy3DNode node) {
    if (node.id == 'heart' ||
        node.id == 'artery' ||
        node.id == 'vein' ||
        node.system == 'vessels') {
      return _hasCardioRisk;
    }
    if (node.id == 'spine' ||
        node.id == 'pelvis' ||
        node.id == 'muscle' ||
        node.id == 'femur') {
      return _hasPostureRisk;
    }
    if (node.id == 'skull' ||
        node.id == 'eye' ||
        (node.id == 'skin' && widget.radiationMsv > 0.85)) {
      return _hasNeuroOrRadiationRisk;
    }
    return false;
  }

  String? _getActiveRiskAlertForNode(Anatomy3DNode node) {
    if (!_isNodeAtRisk(node)) return null;

    if (node.id == 'heart' ||
        node.id == 'artery' ||
        node.id == 'vein' ||
        node.system == 'vessels') {
      return 'CARDIOVASCULAR RISK DETECTED: HR ${widget.heartRateBpm} bpm | BP ${widget.systolicBp}/${widget.diastolicBp} mmHg | AI Risk ${(widget.cardioRisk * 100).toStringAsFixed(1)}%. Possible arrhythmia, hypertension or vascular strain.';
    }
    if (node.id == 'spine' ||
        node.id == 'pelvis' ||
        node.id == 'muscle' ||
        node.id == 'femur') {
      return 'POSTURE & MUSCULOSKELETAL RISK: AI Posture Risk ${(widget.postureRisk * 100).toStringAsFixed(1)}%. Microgravity spinal elongation, disc overload or muscle atrophy risk.';
    }
    if (node.id == 'skull' || node.id == 'eye' || node.id == 'skin') {
      return 'NEUROLOGICAL / RADIATION RISK: Stress ${(widget.neuroStress * 100).toStringAsFixed(0)}% | Radiation ${widget.radiationMsv.toStringAsFixed(2)} mSv/d. Elevated intracranial fluid shift (SANS) or radiation exposure.';
    }
    return null;
  }

  Camera3D _buildCamera(Size viewportSize) {
    final double radius = 17.8 / _zoom;
    final double camX =
        _focusTarget.x + (radius * m.cos(_pitch) * m.sin(_yaw));
    final double camY = _focusTarget.y + (radius * m.sin(_pitch));
    final double camZ =
        _focusTarget.z + (radius * m.cos(_pitch) * m.cos(_yaw));

    final double aspect = viewportSize.height > 0
        ? viewportSize.width / viewportSize.height
        : 1.0;

    return Camera3D(
      position: vm.Vector3(camX, camY, camZ),
      target: _focusTarget.clone(),
      up: vm.Vector3(0.0, 1.0, 0.0),
      fovDegrees: 46.0,
      aspectRatio: aspect,
      zNear: 0.1,
      zFar: 500.0,
    );
  }

  void _focusOnRegion(String regionName) {
    setState(() {
      if (regionName.contains('Neurological')) {
        _active2DFigureZone = 'head';
        _focusTarget = vm.Vector3(0.0, 6.1, 0.0);
        _zoom = 2.35;
      } else if (regionName.contains('Cardiovascular')) {
        _active2DFigureZone = 'chest';
        _focusTarget = vm.Vector3(0.15, 3.6, 0.2);
        _zoom = 2.10;
      } else if (regionName.contains('Musculoskeletal')) {
        _active2DFigureZone = 'core';
        _focusTarget = vm.Vector3(0.0, 1.8, 0.0);
        _zoom = 1.75;
      } else {
        _active2DFigureZone = null;
        _focusTarget = vm.Vector3(0.0, 0.25, 0.0);
        _zoom = 1.0;
      }
    });
  }

  /// Sol üstteki 2 boyutlu insan figüründe bir parçaya basıldığında o kısma zoom yapar
  void _on2DMiniMapZoneTapped(String zone) {
    final double scale = _femaleModel ? 0.94 : 1.0;
    final double sw = (_femaleModel ? 1.55 : 1.80) * scale;

    setState(() {
      // Aynı bölgeye tekrar basılırsa genel görünüme sıfırla
      if (_active2DFigureZone == zone && _zoom > 1.5) {
        _active2DFigureZone = null;
        _focusTarget = vm.Vector3(0.0, 0.25, 0.0);
        _zoom = 1.0;
        _yaw = 0.25;
        _pitch = 0.06;
        return;
      }

      _active2DFigureZone = zone;
      _yaw = 0.0;
      _pitch = 0.05;

      switch (zone) {
        case 'head':
          _focusTarget = vm.Vector3(0.0, 6.25 * scale, 0.2);
          _zoom = 2.55;
          widget.onBodyRegionSelected?.call('Neurological (Head)');
          break;
        case 'chest':
          _focusTarget = vm.Vector3(0.0, 3.75 * scale, 0.2);
          _zoom = 2.15;
          widget.onBodyRegionSelected?.call('Cardiovascular (Heart)');
          break;
        case 'core':
          _focusTarget = vm.Vector3(0.0, 1.15 * scale, 0.0);
          _zoom = 2.05;
          widget.onBodyRegionSelected?.call('Musculoskeletal (Spine)');
          break;
        case 'right_arm':
          _focusTarget = vm.Vector3(-sw * 1.15, 2.35 * scale, 0.1);
          _zoom = 2.10;
          _yaw = -0.35;
          widget.onBodyRegionSelected?.call('Musculoskeletal (Spine)');
          break;
        case 'left_arm':
          _focusTarget = vm.Vector3(sw * 1.15, 2.35 * scale, 0.1);
          _zoom = 2.10;
          _yaw = 0.35;
          widget.onBodyRegionSelected?.call('Musculoskeletal (Spine)');
          break;
        case 'legs':
          _focusTarget = vm.Vector3(0.0, -3.20 * scale, 0.0);
          _zoom = 1.75;
          widget.onBodyRegionSelected?.call('Musculoskeletal (Spine)');
          break;
      }
    });
  }

  List<Anatomy3DNode> _buildAnatomicalNodes(bool female) {
    final List<Anatomy3DNode> nodes = <Anatomy3DNode>[];
    final double scale = female ? 0.94 : 1.0;
    final double sw = (female ? 1.55 : 1.80) * scale;
    final double hw = (female ? 0.82 : 0.72) * scale;

    const Color boneColor = Color(0xFFE6F7FF);
    const Color jointColor = Color(0xFF80E5FF);
    const Color musclePrimary = Color(0xFFFF6A4A);
    const Color muscleSecondary = Color(0xFFD8432E);
    const Color arteryRed = Color(0xFFFF2E4C);
    const Color veinBlue = Color(0xFF2979FF);
    const Color heartCrimson = Color(0xFFFF1744);

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
    // 0. OUTER SKIN LAYER & FACIAL FEATURES (AÇIK MAVİ DERİ, GÖZ, BURUN, YÜZ)
    // =========================================================================
    // Baş ve Alın Derisi
    addSpherePart(
      sys: 'skin',
      id: 'skin',
      name: 'Epidermis & Dermis · Cranial Envelope',
      color: _lightBlueSkin,
      radius: 1.03,
      x: 0,
      y: 6.42,
      z: -0.02,
      segments: 12,
    );
    // Alt Yüz & Çene Hattı Derisi
    addBoxPart(
      sys: 'skin',
      id: 'skin',
      name: 'Dermal Layer · Lower Face & Chin',
      color: _lightBlueSkin,
      w: 1.16,
      h: 0.72,
      d: 1.05,
      x: 0,
      y: 5.75,
      z: 0.14,
    );
    // Burun Köprüsü ve Burun Ucu
    addBoxPart(
      sys: 'skin',
      id: 'skin',
      name: 'Facial Feature · Nasal Bridge (Nose)',
      color: _skinFeatureCyan,
      w: 0.22,
      h: 0.46,
      d: 0.32,
      x: 0,
      y: 6.22,
      z: 0.98,
      rx: -0.18,
    );
    // Ağız / Dudak Konturu
    addBoxPart(
      sys: 'skin',
      id: 'skin',
      name: 'Facial Feature · Labial Contour (Mouth)',
      color: _skinFeatureCyan,
      w: 0.46,
      h: 0.12,
      d: 0.16,
      x: 0,
      y: 5.78,
      z: 0.92,
    );

    // Sağ ve Sol Gözler, Göz Bebekleri, Kaşlar ve Kulaklar
    for (final double s in <double>[-1.0, 1.0]) {
      final String side = s < 0 ? 'Right ' : 'Left ';
      // Göz Küresi (Sklera - Parlak Beyaz)
      addSpherePart(
        sys: 'skin',
        id: 'eye',
        name: '${side}Ocular Globe (Eye & Sclera)',
        color: const Color(0xFFFFFFFF),
        radius: 0.17,
        x: s * 0.34,
        y: 6.38,
        z: 0.88,
        segments: 10,
      );
      // Göz Bebeği & İris (Koyu Uzay Mavisi)
      addSpherePart(
        sys: 'skin',
        id: 'eye',
        name: '${side}Iris & Pupil (SANS Target)',
        color: const Color(0xFF062958),
        radius: 0.085,
        x: s * 0.35,
        y: 6.38,
        z: 1.01,
        segments: 8,
      );
      // Kaş Kemeri Çıkıntısı
      addBoxPart(
        sys: 'skin',
        id: 'skin',
        name: '${side}Supraorbital Ridge (Eyebrow)',
        color: _skinFeatureCyan,
        w: 0.36,
        h: 0.09,
        d: 0.18,
        x: s * 0.35,
        y: 6.60,
        z: 0.92,
        rz: s * -0.08,
      );
      // Kulak Kepçesi (Auricle)
      addBoxPart(
        sys: 'skin',
        id: 'skin',
        name: '${side}Auricle (External Ear)',
        color: _skinFeatureCyan,
        w: 0.16,
        h: 0.44,
        d: 0.28,
        x: s * 1.03,
        y: 6.26,
        z: -0.04,
      );
    }

    // Boyun, Göğüs, Bel ve Pelvis Deri Konturları
    addBoxPart(
      sys: 'skin',
      id: 'skin',
      name: 'Dermal Layer · Neck Contour',
      color: _lightBlueSkin,
      w: 0.90,
      h: 0.78,
      d: 0.82,
      x: 0,
      y: 5.20,
      z: 0.0,
    );
    addBoxPart(
      sys: 'skin',
      id: 'skin',
      name: 'Dermal Layer · Upper Thorax & Chest',
      color: _lightBlueSkin,
      w: sw * 1.65,
      h: 2.15,
      d: 1.52,
      x: 0,
      y: 3.75,
      z: 0.08,
    );
    addBoxPart(
      sys: 'skin',
      id: 'skin',
      name: 'Dermal Layer · Abdominal Waist',
      color: _lightBlueSkin,
      w: hw * 2.35,
      h: 1.55,
      d: 1.32,
      x: 0,
      y: 1.95,
      z: 0.06,
    );
    addBoxPart(
      sys: 'skin',
      id: 'skin',
      name: 'Dermal Layer · Pelvic Envelope',
      color: _lightBlueSkin,
      w: hw * 2.55,
      h: 1.25,
      d: 1.42,
      x: 0,
      y: 0.55,
      z: 0.02,
    );

    // =========================================================================
    // 1. SKELETAL SYSTEM (KEMİK VE EKLEM SİSTEMİ)
    // =========================================================================
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

    for (final double s in <double>[-1.0, 1.0]) {
      final String side = s < 0 ? 'Right ' : 'Left ';

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

      final List<double> sh = <double>[s * sw, 4.45, 0.0];
      final List<double> el = <double>[s * (sw + 0.35), 2.15, 0.05];
      final List<double> wr = <double>[s * (sw + 0.65), 0.15, 0.25];
      final List<double> hp = <double>[s * hw, -0.15, 0.0];
      final List<double> kn = <double>[s * (hw + 0.08), -3.25, 0.08];
      final List<double> an = <double>[s * (hw + 0.12), -6.25, 0.0];

      // Omuz, Kol, El, Uyluk, Bacak ve Ayak Deri (Skin) Detayları
      addSpherePart(
        sys: 'skin',
        id: 'skin',
        name: '${side}Dermal Layer · Shoulder Cap',
        color: _lightBlueSkin,
        radius: 0.50,
        x: sh[0],
        y: sh[1],
        z: sh[2],
        segments: 8,
      );
      addSegmentBar(
        sys: 'skin',
        id: 'skin',
        name: '${side}Dermal Layer · Upper Arm',
        color: _lightBlueSkin,
        p1: sh,
        p2: el,
        thickness: 0.34,
      );
      addSegmentBar(
        sys: 'skin',
        id: 'skin',
        name: '${side}Dermal Layer · Forearm',
        color: _lightBlueSkin,
        p1: el,
        p2: wr,
        thickness: 0.26,
      );
      addBoxPart(
        sys: 'skin',
        id: 'skin',
        name: '${side}Dermal Layer · Hand & Fingers',
        color: _skinFeatureCyan,
        w: 0.34,
        h: 0.72,
        d: 0.22,
        x: wr[0] + (s * 0.05),
        y: wr[1] - 0.44,
        z: wr[2] + 0.05,
      );
      addSegmentBar(
        sys: 'skin',
        id: 'skin',
        name: '${side}Dermal Layer · Thigh',
        color: _lightBlueSkin,
        p1: hp,
        p2: kn,
        thickness: 0.42,
      );
      addSpherePart(
        sys: 'skin',
        id: 'skin',
        name: '${side}Dermal Layer · Patellar Knee Contour',
        color: _skinFeatureCyan,
        radius: 0.34,
        x: kn[0],
        y: kn[1],
        z: kn[2] + 0.05,
        segments: 8,
      );
      addSegmentBar(
        sys: 'skin',
        id: 'skin',
        name: '${side}Dermal Layer · Lower Leg',
        color: _lightBlueSkin,
        p1: kn,
        p2: an,
        thickness: 0.32,
      );
      addBoxPart(
        sys: 'skin',
        id: 'skin',
        name: '${side}Dermal Layer · Foot Envelope',
        color: _skinFeatureCyan,
        w: 0.48,
        h: 0.30,
        d: 1.02,
        x: an[0],
        y: an[1] - 0.18,
        z: an[2] + 0.32,
      );

      // Eklemler
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

      // 2. MUSCULAR SYSTEM
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

      // 3. VASCULAR SYSTEM
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
      if (node.system == 'skin' && !_showSkin) return false;
      if (node.system == 'skeleton' && !_showSkeleton) return false;
      if (node.system == 'muscle' && !_showMuscle) return false;
      if (node.system == 'vessels' && !_showVessels) return false;
      return true;
    }).toList(growable: false);
  }

  // Basılan yer sarı (#FFEA00) kalır; riskli bölge parlak turuncu (#FF6D00 <-> #FFAB00) yanıp söner
  Color _resolveNodeColor(Anatomy3DNode node, double pulseValue) {
    if (identical(node, _selectedNode)) {
      return _selectedYellow;
    }

    if (_isNodeAtRisk(node)) {
      return Color.lerp(
        node.baseColor,
        Color.lerp(_brightOrangeAlert, _brightOrangeGlow, pulseValue)!,
        0.45 + (0.55 * pulseValue),
      )!;
    }

    if (node.id == 'heart') {
      return Color.lerp(
        node.baseColor,
        const Color(0xFFFF8A80),
        0.22 * pulseValue,
      )!;
    }

    return node.baseColor;
  }

  void _handleCanvasTap(Offset localTap, Size viewSize) {
    if (viewSize.width <= 0 || viewSize.height <= 0) return;
    final Camera3D cam = _buildCamera(viewSize);
    final List<Anatomy3DNode> active = _visibleNodes;

    Anatomy3DNode? bestMatch;
    double bestDist = double.infinity;

    for (final Anatomy3DNode node in active) {
      // Göz dışındaki genel deri parçalarının iç organ/kemik seçimini kapatmaması için öncelik
      if (node.system == 'skin' &&
          node.id != 'eye' &&
          (_showSkeleton || _showMuscle || _showVessels) &&
          active.length > 16) {
        continue;
      }

      final vm.Vector4 clip = cam.projectToClipSpace(node.center);
      if (clip.w <= 0.1) continue;

      final double ndcX = clip.x / clip.w;
      final double ndcY = clip.y / clip.w;

      final double sx = (ndcX + 1.0) * 0.5 * viewSize.width;
      final double sy = (1.0 - ndcY) * 0.5 * viewSize.height;

      final double hitPx =
          (node.hitRadius * viewSize.height / clip.w).clamp(18.0, 52.0);
      final double dist = (Offset(sx, sy) - localTap).distance;

      if (dist <= hitPx && dist < bestDist) {
        bestDist = dist;
        bestMatch = node;
      }
    }

    if (bestMatch == null && _showSkin) {
      for (final Anatomy3DNode node in active.where((n) => n.system == 'skin')) {
        final vm.Vector4 clip = cam.projectToClipSpace(node.center);
        if (clip.w <= 0.1) continue;
        final double sx = ((clip.x / clip.w) + 1.0) * 0.5 * viewSize.width;
        final double sy = (1.0 - (clip.y / clip.w)) * 0.5 * viewSize.height;
        final double dist = (Offset(sx, sy) - localTap).distance;
        if (dist <= 46.0 && dist < bestDist) {
          bestDist = dist;
          bestMatch = node;
        }
      }
    }

    if (bestMatch != null) {
      setState(() {
        _selectedNode = bestMatch;
        _focusTarget = bestMatch!.center.clone();
        if (_zoom < 1.40) _zoom = 1.50;
      });
      if (bestMatch.id == 'skull' || bestMatch.id == 'eye') {
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
      if (mode == 'skin') {
        _showSkin = true;
        _showSkeleton = false;
        _showMuscle = false;
        _showVessels = false;
      } else if (mode == 'skeleton') {
        _showSkin = false;
        _showSkeleton = true;
        _showMuscle = false;
        _showVessels = false;
      } else if (mode == 'muscle') {
        _showSkin = false;
        _showSkeleton = false;
        _showMuscle = true;
        _showVessels = false;
      } else if (mode == 'vessels') {
        _showSkin = false;
        _showSkeleton = false;
        _showMuscle = false;
        _showVessels = true;
      } else {
        _showSkin = true;
        _showSkeleton = true;
        _showMuscle = true;
        _showVessels = true;
      }
      _isolateSystem = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool anyRiskActive =
        _hasCardioRisk || _hasPostureRisk || _hasNeuroOrRadiationRisk;

    return Container(
      decoration: BoxDecoration(
        color: NasaColors.stationGrey,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: anyRiskActive
              ? _brightOrangeAlert.withValues(alpha: 0.90)
              : NasaColors.biometricCyan.withValues(alpha: 0.45),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (anyRiskActive
                    ? _brightOrangeAlert
                    : NasaColors.biometricCyan)
                .withValues(alpha: 0.14),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. ÜST BAR
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.radar_rounded,
                            size: 13,
                            color: anyRiskActive
                                ? _brightOrangeAlert
                                : NasaColors.biometricCyan,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              anyRiskActive
                                  ? 'BIOMETRIC SCAN • ANOMALY DETECTED'
                                  : 'PERFECTUM 3D • ACTIVE BIOMETRIC SCAN',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: anyRiskActive
                                    ? _brightOrangeAlert
                                    : NasaColors.biometricCyan,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.gravityLabel} • HR: ${widget.heartRateBpm} BPM • BP: ${widget.systolicBp}/${widget.diastolicBp}',
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
                      label: 'CENTER',
                      icon: Icons.center_focus_strong,
                      onTap: () {
                        setState(() {
                          _yaw = 0.25;
                          _pitch = 0.06;
                          _zoom = 1.0;
                          _focusTarget = vm.Vector3(0.0, 0.25, 0.0);
                          _active2DFigureZone = null;
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

          // 2. SİSTEM FİLTRELERİ (AÇIK MAVİ DERİ + KEMİK + KAS + DAMAR)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildSystemFilterChip(
                    label: 'SKIN (DERMAL)',
                    active: _showSkin,
                    activeColor: _lightBlueSkin,
                    icon: Icons.waves_rounded,
                    onSelected: (bool v) => setState(() => _showSkin = v),
                    onDoubleTap: () => _applySystemPreset('skin'),
                  ),
                  const SizedBox(width: 6),
                  _buildSystemFilterChip(
                    label: 'SKELETAL (BONE)',
                    active: _showSkeleton,
                    activeColor: const Color(0xFFE6F7FF),
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

          // Hızlı Görünüm Modları
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildPresetButton(
                    'Only Skin',
                    () => _applySystemPreset('skin'),
                  ),
                  const SizedBox(width: 6),
                  _buildPresetButton(
                    'Only Bone',
                    () => _applySystemPreset('skeleton'),
                  ),
                  const SizedBox(width: 6),
                  _buildPresetButton(
                    'Only Muscle',
                    () => _applySystemPreset('muscle'),
                  ),
                  const SizedBox(width: 6),
                  _buildPresetButton(
                    'Only Vessels',
                    () => _applySystemPreset('vessels'),
                  ),
                  const SizedBox(width: 6),
                  _buildPresetButton(
                    'All Systems',
                    () => _applySystemPreset('all'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 3. SINIRLANDIRILMIŞ KARE 3D ALANI + SOL ÜST 2B İNSAN FİGÜRÜ (MINI-MAP)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 410,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: NasaColors.darkMatter,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: anyRiskActive
                        ? _brightOrangeAlert.withValues(alpha: 0.55)
                        : NasaColors.biometricCyan.withValues(alpha: 0.28),
                    width: 1.0,
                  ),
                ),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final Size viewportSize = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    return Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        // 3D Render Katmanı
                        Listener(
                          onPointerSignal: (PointerSignalEvent event) {
                            if (event is PointerScrollEvent) {
                              setState(() {
                                final double factor =
                                    m.exp(-event.scrollDelta.dy * 0.0015);
                                _zoom = (_zoom * factor).clamp(0.65, 3.8);
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
                                      .clamp(0.65, 3.8);
                                  _focusTarget.y = (_focusTarget.y +
                                          d.focalPointDelta.dy * 0.025)
                                      .clamp(-6.5, 6.8);
                                  _focusTarget.x = (_focusTarget.x -
                                          d.focalPointDelta.dx * 0.025)
                                      .clamp(-2.5, 2.5);
                                } else {
                                  _yaw -= d.focalPointDelta.dx * 0.012;
                                  _pitch = (_pitch +
                                          d.focalPointDelta.dy * 0.012)
                                      .clamp(-1.25, 1.25);
                                }
                              });
                            },
                            onTapUp: (TapUpDetails d) =>
                                _handleCanvasTap(d.localPosition, viewportSize),
                            child: AnimatedBuilder(
                              animation: Listenable.merge(<Listenable>[
                                _pulseController,
                                _scanController,
                              ]),
                              builder: (BuildContext context, _) {
                                final Camera3D camera =
                                    _buildCamera(viewportSize);
                                final List<Anatomy3DNode> activeNodes =
                                    _visibleNodes;

                                final List<Mesh3D> renderedMeshes = activeNodes
                                    .map(
                                      (Anatomy3DNode n) => n.toMesh3D(
                                        _resolveNodeColor(
                                          n,
                                          _pulseController.value,
                                        ),
                                      ),
                                    )
                                    .toList(growable: false);

                                final vm.Vector3 lightDir =
                                    (camera.position - camera.target)
                                      ..normalize();

                                return Stack(
                                  children: [
                                    Scene3D(
                                      camera: camera,
                                      meshes: renderedMeshes,
                                      lightDirection: lightDir,
                                      backgroundColor: NasaColors.darkMatter,
                                      enableFog: false,
                                    ),
                                    // Tarama ışıltısı ve parlak turuncu uyarı katmanı
                                    IgnorePointer(
                                      child: CustomPaint(
                                        size: viewportSize,
                                        painter: _BiometricScannerOverlayPainter(
                                          scanProgress: _scanController.value,
                                          pulseValue: _pulseController.value,
                                          hasAlert: anyRiskActive,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),

                        // SOL ÜST: 2 BOYUTLU İNTERAKTİF İNSAN FİGÜRÜ (Bölgeye Tıklayınca Zoom Yapar)
                        Positioned(
                          left: 10,
                          top: 10,
                          child: AnimatedBuilder(
                            animation: _pulseController,
                            builder: (BuildContext context, _) {
                              return _Interactive2DBodyMiniMap(
                                activeZone: _active2DFigureZone,
                                headRisk: _hasNeuroOrRadiationRisk,
                                chestRisk: _hasCardioRisk,
                                coreAndLimbRisk: _hasPostureRisk,
                                pulseValue: _pulseController.value,
                                onZoneTap: _on2DMiniMapZoneTapped,
                              );
                            },
                          ),
                        ),

                        // Sağ Üst Lejant (Deri / Kemik / Kas / Damar / Parlak Turuncu Uyarı)
                        Positioned(
                          right: 10,
                          top: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: NasaColors.darkMatter.withValues(
                                alpha: 0.84,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: NasaColors.nebulaGrey.withValues(
                                  alpha: 0.25,
                                ),
                              ),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _LegendDot(
                                  color: _lightBlueSkin,
                                  label: 'Dermal Skin & Eyes',
                                ),
                                SizedBox(height: 3),
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
                                  label: 'Artery / Veins',
                                ),
                                SizedBox(height: 3),
                                _LegendDot(
                                  color: _brightOrangeAlert,
                                  label: 'Orange Risk Pulse',
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Seçilen Anatomik Yapı ve Risk Bilgi Kartı
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
            ),
          ),

          // 4. ALT KONTROLLER: Dikey Gezinme (Y-Focus), Zoom Slider ve Bölge Odaklama
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.swap_vert_rounded,
                      size: 15,
                      color: NasaColors.nebulaGrey,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'FOCUS Y',
                      style: TextStyle(
                        color: NasaColors.nebulaGrey,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: _focusTarget.y.clamp(-6.0, 6.5),
                        min: -6.0,
                        max: 6.5,
                        activeColor: NasaColors.biometricCyan,
                        inactiveColor: NasaColors.darkMatter,
                        onChanged: (double v) => setState(() {
                          _focusTarget = vm.Vector3(
                            _focusTarget.x,
                            v,
                            _focusTarget.z,
                          );
                        }),
                      ),
                    ),
                    const Icon(
                      Icons.zoom_in_rounded,
                      size: 15,
                      color: NasaColors.nebulaGrey,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'ZOOM',
                      style: TextStyle(
                        color: NasaColors.nebulaGrey,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: _zoom.clamp(0.65, 3.8),
                        min: 0.65,
                        max: 3.8,
                        activeColor: NasaColors.biometricCyan,
                        inactiveColor: NasaColors.darkMatter,
                        onChanged: (double v) => setState(() => _zoom = v),
                      ),
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
                    final bool regionRisk =
                        (region.contains('Neurological') &&
                            _hasNeuroOrRadiationRisk) ||
                        (region.contains('Cardiovascular') && _hasCardioRisk) ||
                        (region.contains('Musculoskeletal') &&
                            _hasPostureRisk);

                    return GestureDetector(
                      onTap: () {
                        widget.onBodyRegionSelected?.call(region);
                        _focusOnRegion(region);
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
                            color: regionRisk
                                ? _brightOrangeAlert
                                : (isSelected
                                      ? NasaColors.biometricCyan
                                      : NasaColors.nebulaGrey.withValues(
                                          alpha: 0.3,
                                        )),
                            width: regionRisk ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (regionRisk) ...[
                              const Icon(
                                Icons.warning_amber_rounded,
                                size: 12,
                                color: _brightOrangeAlert,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              region.split(' ').first,
                              style: TextStyle(
                                color: regionRisk
                                    ? _brightOrangeAlert
                                    : (isSelected
                                          ? NasaColors.pureWhite
                                          : NasaColors.nebulaGrey),
                                fontSize: 11,
                                fontWeight: (isSelected || regionRisk)
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
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
    final String? activeRiskAlert = _getActiveRiskAlertForNode(node);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: NasaColors.darkMatter.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: activeRiskAlert != null ? _brightOrangeAlert : _selectedYellow,
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                activeRiskAlert != null
                    ? Icons.warning_amber_rounded
                    : Icons.hub_rounded,
                color: activeRiskAlert != null
                    ? _brightOrangeAlert
                    : _selectedYellow,
                size: 15,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${node.name.toUpperCase()} (${node.system.toUpperCase()})',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: activeRiskAlert != null
                        ? _brightOrangeAlert
                        : _selectedYellow,
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
          if (activeRiskAlert != null) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _brightOrangeAlert.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _brightOrangeAlert.withValues(alpha: 0.85),
                ),
              ),
              child: Text(
                activeRiskAlert,
                style: const TextStyle(
                  color: _brightOrangeGlow,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
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

/// Sol üst köşede yer alan 2 boyutlu interaktif insan figürü (parçalarına basılınca o bölgeye zoom yapar)
class _Interactive2DBodyMiniMap extends StatelessWidget {
  final String? activeZone;
  final bool headRisk;
  final bool chestRisk;
  final bool coreAndLimbRisk;
  final double pulseValue;
  final ValueChanged<String> onZoneTap;

  const _Interactive2DBodyMiniMap({
    required this.activeZone,
    required this.headRisk,
    required this.chestRisk,
    required this.coreAndLimbRisk,
    required this.pulseValue,
    required this.onZoneTap,
  });

  Color _zoneColor(String zone, bool hasRisk) {
    if (activeZone == zone) {
      return const Color(0xFFFFEA00); // Seçili bölge parlak sarı
    }
    if (hasRisk) {
      return Color.lerp(
        const Color(0xFFFF6D00),
        const Color(0xFFFFAB00),
        pulseValue,
      )!;
    }
    return const Color(0xFF7CE8FF).withValues(alpha: 0.55);
  }

  Widget _buildPartBox({
    required String zone,
    required double width,
    required double height,
    required bool hasRisk,
    double borderRadius = 4,
    Widget? child,
  }) {
    final bool isSelected = activeZone == zone;
    final Color fill = _zoneColor(zone, hasRisk);
    return GestureDetector(
      onTap: () => onZoneTap(zone),
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill.withValues(alpha: isSelected || hasRisk ? 0.85 : 0.32),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFFEA00)
                : (hasRisk ? const Color(0xFFFF6D00) : NasaColors.biometricCyan),
            width: isSelected || hasRisk ? 1.4 : 0.9,
          ),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
      decoration: BoxDecoration(
        color: NasaColors.darkMatter.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: NasaColors.biometricCyan.withValues(alpha: 0.38),
          width: 1.0,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '2D ZOOM',
            style: TextStyle(
              color: NasaColors.biometricCyan,
              fontSize: 7.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 5),
          // 1. Kafa (Head)
          _buildPartBox(
            zone: 'head',
            width: 18,
            height: 18,
            hasRisk: headRisk,
            borderRadius: 9,
          ),
          const SizedBox(height: 2),
          // 2. Kollar ve Gövde (Chest + Core)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sağ Kol (Right Arm)
              _buildPartBox(
                zone: 'right_arm',
                width: 9,
                height: 36,
                hasRisk: coreAndLimbRisk,
                borderRadius: 4,
              ),
              const SizedBox(width: 2),
              // Göğüs (Chest/Heart) + Karın/Omurga (Core/Spine)
              Column(
                children: [
                  _buildPartBox(
                    zone: 'chest',
                    width: 22,
                    height: 18,
                    hasRisk: chestRisk,
                    borderRadius: 4,
                    child: const Icon(
                      Icons.favorite,
                      size: 8,
                      color: Color(0xFFFF2E4C),
                    ),
                  ),
                  const SizedBox(height: 2),
                  _buildPartBox(
                    zone: 'core',
                    width: 20,
                    height: 16,
                    hasRisk: coreAndLimbRisk,
                    borderRadius: 4,
                  ),
                ],
              ),
              const SizedBox(width: 2),
              // Sol Kol (Left Arm)
              _buildPartBox(
                zone: 'left_arm',
                width: 9,
                height: 36,
                hasRisk: coreAndLimbRisk,
                borderRadius: 4,
              ),
            ],
          ),
          const SizedBox(height: 2),
          // 3. Bacaklar (Legs)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPartBox(
                zone: 'legs',
                width: 9,
                height: 34,
                hasRisk: coreAndLimbRisk,
                borderRadius: 4,
              ),
              const SizedBox(width: 3),
              _buildPartBox(
                zone: 'legs',
                width: 9,
                height: 34,
                hasRisk: coreAndLimbRisk,
                borderRadius: 4,
              ),
            ],
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

/// 3D Sahnenin üzerinde tarama yaptığını belli eden hafif fütüristik lazer ve parlak turuncu uyarı ışıltısı
class _BiometricScannerOverlayPainter extends CustomPainter {
  final double scanProgress;
  final double pulseValue;
  final bool hasAlert;

  _BiometricScannerOverlayPainter({
    required this.scanProgress,
    required this.pulseValue,
    required this.hasAlert,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Color primaryGlow = hasAlert
        ? const Color(0xFFFF6D00)
        : NasaColors.biometricCyan;

    // 1. Hafif arka plan biyometrik ızgara ışıltısı
    final Paint gridPaint = Paint()
      ..color = NasaColors.biometricCyan.withValues(alpha: 0.045)
      ..strokeWidth = 0.7;

    const double step = 32.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 2. Yukarıdan aşağıya süzülen tarama (Scanline) ışıltısı
    final double scanY = size.height * scanProgress;
    final Rect glowRect = Rect.fromLTWH(
      0,
      (scanY - 26).clamp(0.0, size.height),
      size.width,
      52,
    );

    final Paint scanGlowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          primaryGlow.withValues(alpha: 0.0),
          primaryGlow.withValues(alpha: hasAlert ? 0.22 : 0.14),
          primaryGlow.withValues(alpha: 0.0),
        ],
      ).createShader(glowRect);

    canvas.drawRect(glowRect, scanGlowPaint);

    final Paint scanLinePaint = Paint()
      ..color = primaryGlow.withValues(alpha: hasAlert ? 0.65 : 0.45)
      ..strokeWidth = 1.3;
    canvas.drawLine(
      Offset(12, scanY),
      Offset(size.width - 12, scanY),
      scanLinePaint,
    );

    // 3. Köşe HUD Tarama Çerçeveleri (Uyarı durumunda parlak turuncu yanıp söner)
    final Paint bracketPaint = Paint()
      ..color = primaryGlow.withValues(alpha: 0.40 + (0.35 * pulseValue))
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    const double bLen = 16.0;
    const double pad = 6.0;
    // Sol Üst
    canvas.drawLine(
      const Offset(pad, pad),
      const Offset(pad + bLen, pad),
      bracketPaint,
    );
    canvas.drawLine(
      const Offset(pad, pad),
      const Offset(pad, pad + bLen),
      bracketPaint,
    );
    // Sağ Üst
    canvas.drawLine(
      Offset(size.width - pad, pad),
      Offset(size.width - pad - bLen, pad),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(size.width - pad, pad),
      Offset(size.width - pad, pad + bLen),
      bracketPaint,
    );
    // Sol Alt
    canvas.drawLine(
      Offset(pad, size.height - pad),
      Offset(pad + bLen, size.height - pad),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(pad, size.height - pad),
      Offset(pad, size.height - pad - bLen),
      bracketPaint,
    );
    // Sağ Alt
    canvas.drawLine(
      Offset(size.width - pad, size.height - pad),
      Offset(size.width - pad - bLen, size.height - pad),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(size.width - pad, size.height - pad),
      Offset(size.width - pad, size.height - pad - bLen),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BiometricScannerOverlayPainter oldDelegate) =>
      oldDelegate.scanProgress != scanProgress ||
      oldDelegate.pulseValue != pulseValue ||
      oldDelegate.hasAlert != hasAlert;
}