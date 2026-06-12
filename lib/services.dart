import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'models.dart';

class Services {
  static const _photon = 'https://photon.komoot.io';
  static const _osrm = 'https://router.project-osrm.org';
  static const _overpass = 'https://overpass-api.de/api/interpreter';
  static const _meteo = 'https://api.open-meteo.com/v1/forecast';

  /// Current GPS position. Returns null if unavailable / denied.
  static Future<LatLng?> currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return null;
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return LatLng(p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Live GPS position stream for trip tracking.
  static Stream<Position> positionStream() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 4,
        ),
      );

  /// Address autocomplete (street-level), biased to [near].
  static const double _maxNearMeters = 200000; // 200 km radius for "near me"

  static Future<List<Suggestion>> geocode(String q, {LatLng? near}) async {
    if (q.trim().length < 2) return [];
    // Run a region-restricted venue search (Nominatim) and a street search (Photon)
    // together, then keep only what is near the user, nearest first.
    final futures = <Future<List<Suggestion>>>[_photonSuggest(q, near)];
    if (near != null) futures.add(_nominatimSuggest(q, near: near, bounded: true));
    final lists = await Future.wait(futures);

    final merged = <Suggestion>[];
    final seen = <String>{};
    for (final l in lists) {
      for (final s in l) {
        final key = '${s.pos.latitude.toStringAsFixed(4)},${s.pos.longitude.toStringAsFixed(4)}';
        if (seen.add(key)) merged.add(s);
      }
    }
    if (near != null) {
      return merged.where((s) => _distM(near, s.pos) <= _maxNearMeters).toList()
        ..sort((a, b) => _distM(near, a.pos).compareTo(_distM(near, b.pos)));
    }
    return merged;
  }

  static Future<List<Suggestion>> _photonSuggest(String q, LatLng? near) async {
    final bias = near != null ? '&lat=${near.latitude}&lon=${near.longitude}&location_bias_scale=0.6' : '';
    final url = '$_photon/api/?q=${Uri.encodeComponent(q)}&limit=15&lang=en$bias';
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      final data = jsonDecode(r.body);
      final feats = (data['features'] as List?) ?? [];
      return feats.map<Suggestion>((f) {
        final p = f['properties'] ?? {};
        final c = f['geometry']['coordinates'];
        return Suggestion(
          _mainLabel(p),
          _secLabel(p),
          LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
          (p['osm_value'] ?? '').toString(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static double _distM(LatLng a, LatLng b) => const Distance().as(LengthUnit.Meter, a, b);

  static Future<List<Suggestion>> _nominatimSuggest(String q, {LatLng? near, bool bounded = false}) async {
    if (q.trim().length < 3) return [];
    try {
      String box = '';
      if (near != null) {
        final lat = near.latitude, lon = near.longitude;
        final deg = bounded ? 1.2 : 1.5;
        box = '&viewbox=${lon - deg},${lat + deg},${lon + deg},${lat - deg}&bounded=${bounded ? 1 : 0}';
      }
      final url =
          'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(q)}&format=jsonv2&accept-language=en&limit=10$box';
      final r = await http.get(Uri.parse(url),
          headers: {'User-Agent': 'TravellyApp/1.0 (QUT student project)', 'Accept-Language': 'en'}).timeout(const Duration(seconds: 12));
      final d = jsonDecode(r.body);
      if (d is! List) return [];
      final list = d.map<Suggestion>((e) {
        final full = (e['display_name'] as String?) ?? 'Unknown';
        final parts = full.split(',');
        final main = parts.first.trim();
        final sec = parts.length > 1
            ? parts.sublist(1, parts.length > 3 ? 3 : parts.length).map((x) => x.toString().trim()).join(', ')
            : '';
        return Suggestion(
          main,
          sec,
          LatLng(double.parse(e['lat'].toString()), double.parse(e['lon'].toString())),
          (e['type'] ?? '').toString(),
        );
      }).toList();
      if (near != null) {
        final near2 = list.where((s) => _distM(near, s.pos) <= _maxNearMeters).toList()
          ..sort((a, b) => _distM(near, a.pos).compareTo(_distM(near, b.pos)));
        return near2;
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<LatLng?> geocodeOne(String q, {LatLng? near}) async {
    // Try Photon first - good for streets/POIs
    final list = await geocode(q, near: near);
    if (list.isNotEmpty) return list.first.pos;
    // Fallback to Nominatim - good for towns/cities/regions
    try {
      final url =
          'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(q)}&format=json&accept-language=en&limit=1';
      final r = await http.get(Uri.parse(url),
          headers: {'User-Agent': 'TravellyApp/1.0 (QUT student project)', 'Accept-Language': 'en'}).timeout(const Duration(seconds: 15));
      final d = jsonDecode(r.body);
      if (d is List && d.isNotEmpty) {
        return LatLng(double.parse(d[0]['lat'].toString()), double.parse(d[0]['lon'].toString()));
      }
    } catch (_) {}
    return null;
  }

  static Future<String> reverseGeocode(LatLng p) async {
    // Photon reverse
    try {
      final r = await http
          .get(Uri.parse('$_photon/reverse?lat=${p.latitude}&lon=${p.longitude}&lang=en'))
          .timeout(const Duration(seconds: 12));
      final d = jsonDecode(r.body);
      final feats = (d['features'] as List?) ?? [];
      if (feats.isNotEmpty) {
        final pr = feats[0]['properties'] ?? {};
        final label = pr['district'] ?? pr['locality'] ?? pr['suburb'] ??
            pr['city'] ?? pr['name'] ?? pr['street'];
        if (label != null) return label.toString();
      }
    } catch (_) {}
    // Nominatim reverse fallback (good suburb names)
    try {
      final r = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/reverse?lat=${p.latitude}&lon=${p.longitude}&format=json&zoom=14'),
        headers: {'User-Agent': 'TravellyApp/1.0 (QUT student project)'},
      ).timeout(const Duration(seconds: 12));
      final d = jsonDecode(r.body);
      final a = d['address'] ?? {};
      final label = a['suburb'] ?? a['neighbourhood'] ?? a['city_district'] ??
          a['town'] ?? a['city'] ?? a['village'] ?? a['municipality'];
      if (label != null) return label.toString();
    } catch (_) {}
    return 'your area';
  }

  static String _mainLabel(Map p) {
    if (p['housenumber'] != null && p['street'] != null) {
      return '${p['housenumber']} ${p['street']}';
    }
    if (p['street'] != null && p['name'] != null && p['name'] != p['street']) {
      return p['name'];
    }
    return p['name'] ?? p['street'] ?? 'Unknown';
  }

  static String _secLabel(Map p) {
    final parts = [p['district'], p['city'], p['state'], p['postcode']]
        .where((e) => e != null)
        .map((e) => e.toString())
        .toSet()
        .toList();
    return parts.join(', ');
  }

  /// Up to 3 real alternative road routes (OSRM driving profile).
  static Future<List<BaseRoute>> routes(LatLng from, LatLng to) async {
    final url =
        '$_osrm/route/v1/driving/${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
        '?alternatives=3&overview=full&geometries=geojson';
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      final d = jsonDecode(r.body);
      final rs = (d['routes'] as List?) ?? [];
      return rs.map((rt) {
        final pts = (rt['geometry']['coordinates'] as List)
            .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
        return BaseRoute(
          (rt['distance'] as num).toDouble() / 1000.0,
          (rt['duration'] as num).toDouble(),
          pts,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Nearest named bus stop or train station (OpenStreetMap Overpass).
  static Future<StopInfo?> nearestStop(LatLng p) async {
    final q = '[out:json][timeout:20];('
        'node(around:2500,${p.latitude},${p.longitude})[highway=bus_stop];'
        'node(around:2500,${p.latitude},${p.longitude})[public_transport=platform];'
        'node(around:5000,${p.latitude},${p.longitude})[railway=station];'
        'node(around:5000,${p.latitude},${p.longitude})[railway=halt];'
        ');out body 50;';
    try {
      final r = await http
          .post(Uri.parse(_overpass), body: {'data': q})
          .timeout(const Duration(seconds: 22));
      final d = jsonDecode(r.body);
      final els = (d['elements'] as List?) ?? [];
      StopInfo? best;
      double bd = 1e9;
      final dist = const Distance();
      for (final e in els) {
        if (e['lat'] == null) continue;
        final tags = e['tags'] ?? {};
        final name = tags['name'] ?? tags['name:en'];
        if (name == null) continue;
        final isTrain = tags['railway'] == 'station' || tags['railway'] == 'halt';
        final pos = LatLng((e['lat'] as num).toDouble(), (e['lon'] as num).toDouble());
        var dd = dist.as(LengthUnit.Kilometer, p, pos);
        if (isTrain) dd -= 0.25; // gently favour rail
        if (dd < bd) {
          bd = dd;
          best = StopInfo(name, isTrain ? 'train' : 'bus', pos);
        }
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  /// Nearest named bus stop, train station AND ferry terminal (OpenStreetMap).
  static Future<({StopInfo? bus, StopInfo? train, StopInfo? ferry})> nearestByType(LatLng p) async {
    final q = '[out:json][timeout:20];('
        'node(around:2500,${p.latitude},${p.longitude})[highway=bus_stop];'
        'node(around:2500,${p.latitude},${p.longitude})[public_transport=platform];'
        'node(around:5000,${p.latitude},${p.longitude})[railway=station];'
        'node(around:5000,${p.latitude},${p.longitude})[railway=halt];'
        'node(around:4000,${p.latitude},${p.longitude})[amenity=ferry_terminal];'
        'node(around:4000,${p.latitude},${p.longitude})[ferry=yes];'
        ');out body 80;';
    try {
      final r = await http
          .post(Uri.parse(_overpass), body: {'data': q})
          .timeout(const Duration(seconds: 22));
      final d = jsonDecode(r.body);
      final els = (d['elements'] as List?) ?? [];
      StopInfo? bus, train, ferry;
      double bb = 1e9, tb = 1e9, fb = 1e9;
      final dist = const Distance();
      for (final e in els) {
        if (e['lat'] == null) continue;
        final tags = e['tags'] ?? {};
        final name = tags['name'] ?? tags['name:en'];
        if (name == null) continue;
        final isTrain = tags['railway'] == 'station' || tags['railway'] == 'halt';
        final isFerry = tags['amenity'] == 'ferry_terminal' || tags['ferry'] == 'yes';
        final pos = LatLng((e['lat'] as num).toDouble(), (e['lon'] as num).toDouble());
        final dd = dist.as(LengthUnit.Kilometer, p, pos);
        if (isFerry) {
          if (dd < fb) { fb = dd; ferry = StopInfo(name, 'ferry', pos); }
        } else if (isTrain) {
          if (dd < tb) { tb = dd; train = StopInfo(name, 'train', pos); }
        } else {
          if (dd < bb) { bb = dd; bus = StopInfo(name, 'bus', pos); }
        }
      }
      return (bus: bus, train: train, ferry: ferry);
    } catch (_) {
      return (bus: null, train: null, ferry: null);
    }
  }

  static Future<Map<String, dynamic>?> weather(LatLng p) async {
    try {
      final r = await http
          .get(Uri.parse(
              '$_meteo?latitude=${p.latitude}&longitude=${p.longitude}&current=temperature_2m,weather_code'))
          .timeout(const Duration(seconds: 10));
      final d = jsonDecode(r.body);
      return d['current'];
    } catch (_) {
      return null;
    }
  }
}

String wxEmoji(int? code) {
  if (code == null) return '⛅';
  if (code == 0) return '☀️';
  if (code <= 3) return '⛅';
  if (code <= 48) return '🌫️';
  if (code <= 67) return '🌧️';
  if (code <= 77) return '🌨️';
  if (code <= 82) return '🌦️';
  return '⛈️';
}
