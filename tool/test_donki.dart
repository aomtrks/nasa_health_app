// tool/test_donki.dart
// Run from the project root:   dart run tool/test_donki.dart
//
// 1) Calls the NASA CCMC DONKI endpoints directly and prints status + counts.
// 2) Runs NasaSpaceWeatherService and prints what the app would show.

import 'package:dio/dio.dart';
import 'package:nasa_health_app/services/nasa_space_weather_service.dart';

String _fmt(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<void> main() async {
  final DateTime end = DateTime.now().toUtc();
  final DateTime start = end.subtract(const Duration(days: 7));
  final Dio dio = Dio(BaseOptions(
    baseUrl: 'https://ccmc.gsfc.nasa.gov/DONKI-API/get',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  print('=== 1. RAW API CHECK (${_fmt(start)} -> ${_fmt(end)}) ===');
  for (final String type in <String>['FLR', 'SEP', 'GST']) {
    try {
      final Response<dynamic> res = await dio.get<dynamic>(
        '/$type',
        queryParameters: <String, String>{
          'startDate': _fmt(start),
          'endDate': _fmt(end),
        },
      );
      final dynamic data = res.data;
      final int count = data is List ? data.length : -1;
      print('$type -> HTTP ${res.statusCode}, events: $count');
      if (type == 'FLR' && data is List && data.isNotEmpty) {
        final Map<String, dynamic> first = data.first as Map<String, dynamic>;
        print('   first flare: class=${first['classType']} '
            'peak=${first['peakTime']} region=${first['activeRegionNum']}');
      }
    } catch (e) {
      print('$type -> FAILED: $e');
    }
  }

  print('\n=== 2. YOUR SERVICE CLASS ===');
  final NasaSpaceWeatherService service = NasaSpaceWeatherService();
  final SpaceWeatherSnapshot? snap = await service.fetchRecent(days: 7);
  if (service.lastError != null) {
    print('Last error: ${service.lastError}');
  }
  if (snap == null) {
    print('Service returned null -> all requests failed.');
    return;
  }
  print('source:            ${snap.isCached ? "CACHED (saved copy, ${snap.age.inMinutes} min old)" : "LIVE"}');
  print('flares:            ${snap.solarFlares}');
  print('strongest flare:   ${snap.strongestFlare ?? "none"}');
  print('SEP events:        ${snap.energeticParticleEvents}');
  print('geomagnetic storm: ${snap.geomagneticStorm}');
  print('status label:      ${snap.statusLabel}');
  print('radiation x:       ${snap.radiationMultiplier}');
  print('\nIf the counts in section 2 match section 1, the code is working.');
}