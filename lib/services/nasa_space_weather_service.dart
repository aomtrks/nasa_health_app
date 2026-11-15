// lib/services/nasa_space_weather_service.dart
//
// Space weather data from NASA DONKI (Space Weather Database Of
// Notifications, Knowledge, Information), operated by NASA's Community
// Coordinated Modeling Center (CCMC), NASA Goddard Space Flight Center.
// API: https://ccmc.gsfc.nasa.gov/DONKI-API  (no API key required)
// Credit: "Space weather data: NASA CCMC DONKI"
//
// Offline support: the last successful result is saved to a small JSON
// file on the device and used when the network is unavailable.

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

class SpaceWeatherSnapshot {
  final int solarFlares;
  final String? strongestFlare;
  final int energeticParticleEvents;
  final bool geomagneticStorm;
  final DateTime fetchedAt;

  /// true when this data came from the on-device copy (no network).
  final bool isCached;

  const SpaceWeatherSnapshot({
    required this.solarFlares,
    required this.strongestFlare,
    required this.energeticParticleEvents,
    required this.geomagneticStorm,
    required this.fetchedAt,
    this.isCached = false,
  });

  Duration get age => DateTime.now().difference(fetchedAt);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'solarFlares': solarFlares,
        'strongestFlare': strongestFlare,
        'sep': energeticParticleEvents,
        'gst': geomagneticStorm,
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  factory SpaceWeatherSnapshot.fromJson(Map<String, dynamic> m,
      {bool cached = false}) {
    return SpaceWeatherSnapshot(
      solarFlares: (m['solarFlares'] as num).toInt(),
      strongestFlare: m['strongestFlare'] as String?,
      energeticParticleEvents: (m['sep'] as num).toInt(),
      geomagneticStorm: m['gst'] as bool,
      fetchedAt: DateTime.parse(m['fetchedAt'] as String),
      isCached: cached,
    );
  }

  String get statusLabel {
    if (energeticParticleEvents > 0) return 'SOLAR SPE WARN';
    if (strongestFlare != null && strongestFlare!.startsWith('X')) {
      return 'X-CLASS FLARE';
    }
    if (geomagneticStorm) return 'GEOMAGNETIC STORM';
    return 'MAGNETOSPHERE OK';
  }

  /// Heuristic multiplier for the demo - NOT a dosimetry measurement.
  double get radiationMultiplier {
    if (energeticParticleEvents > 0) return 1.6;
    if (strongestFlare != null && strongestFlare!.startsWith('X')) return 1.4;
    if (strongestFlare != null && strongestFlare!.startsWith('M')) return 1.2;
    if (geomagneticStorm) return 1.15;
    return 1.0;
  }
}

class NasaSpaceWeatherService {
  NasaSpaceWeatherService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://ccmc.gsfc.nasa.gov/DONKI-API/get',
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ));

  final Dio _dio;

  /// Last error message from fetchRecent (null if the last call succeeded).
  String? lastError;

  // Cached data older than this describes a stale window, so it is ignored.
  static const Duration _maxCacheAge = Duration(days: 7);

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  File get _cacheFile =>
      File('${Directory.systemTemp.path}/nasa_donki_cache.json');

  Future<void> _saveCache(SpaceWeatherSnapshot s) async {
    try {
      await _cacheFile.writeAsString(jsonEncode(s.toJson()));
    } catch (e) {
      lastError = 'cache write: $e';
    }
  }

  Future<SpaceWeatherSnapshot?> _loadCache() async {
    try {
      if (!await _cacheFile.exists()) return null;
      final Map<String, dynamic> m =
          jsonDecode(await _cacheFile.readAsString()) as Map<String, dynamic>;
      final SpaceWeatherSnapshot s =
          SpaceWeatherSnapshot.fromJson(m, cached: true);
      return s.age > _maxCacheAge ? null : s;
    } catch (_) {
      return null;
    }
  }

  Future<List<dynamic>> _get(String path, DateTime start, DateTime end) async {
    final Response<dynamic> res = await _dio.get<dynamic>(
      path,
      queryParameters: <String, String>{
        'startDate': _fmt(start),
        'endDate': _fmt(end),
      },
    );
    return (res.data is List) ? res.data as List<dynamic> : <dynamic>[];
  }

  /// Live data when online (and saves it), saved data when offline,
  /// null only if there is neither.
  Future<SpaceWeatherSnapshot?> fetchRecent({int days = 7}) async {
    lastError = null;
    final DateTime end = DateTime.now().toUtc();
    final DateTime start = end.subtract(Duration(days: days));

    int failures = 0;
    Future<List<dynamic>> safe(String path) async {
      try {
        return await _get(path, start, end);
      } catch (e) {
        failures++;
        lastError = '$path: $e';
        return <dynamic>[];
      }
    }

    final List<dynamic> flares = await safe('/FLR');
    final List<dynamic> sep = await safe('/SEP');
    final List<dynamic> gst = await safe('/GST');

    // Any failure -> prefer the last complete saved result over partial data.
    if (failures > 0) {
      final SpaceWeatherSnapshot? cached = await _loadCache();
      if (cached != null) return cached;
      if (failures == 3) return null;
    }

    String? strongest;
    double best = -1;
    for (final dynamic f in flares) {
      if (f is! Map) continue;
      final dynamic raw = f['classType'];
      if (raw is! String || raw.isEmpty) continue;
      final double score = _flareScore(raw);
      if (score > best) {
        best = score;
        strongest = raw;
      }
    }

    final SpaceWeatherSnapshot snap = SpaceWeatherSnapshot(
      solarFlares: flares.length,
      strongestFlare: strongest,
      energeticParticleEvents: sep.length,
      geomagneticStorm: gst.isNotEmpty,
      fetchedAt: DateTime.now(),
    );
    if (failures == 0) await _saveCache(snap); // only save complete results
    return snap;
  }

  static double _flareScore(String cls) {
    const Map<String, double> base = <String, double>{
      'A': 0, 'B': 1, 'C': 2, 'M': 3, 'X': 4,
    };
    final double b = base[cls[0].toUpperCase()] ?? 0;
    final double n = double.tryParse(cls.substring(1)) ?? 0;
    return b + n / 10;
  }
}