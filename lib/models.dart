import 'package:latlong2/latlong.dart';

const double kCarCo2 = 0.192; // kg CO2 per km — petrol car baseline

class TravelMode {
  final String key;
  final String label;
  final String icon; // emoji
  final double speedKmh;
  const TravelMode(this.key, this.label, this.icon, this.speedKmh);
}

const Map<String, TravelMode> kModes = {
  'foot': TravelMode('foot', 'Walking', '🚶', 5),
  'bike': TravelMode('bike', 'Cycling', '🚲', 16),
  'scooter': TravelMode('scooter', 'E-scooter', '🛴', 18),
  'transit': TravelMode('transit', 'Public transport', '🚌', 24),
  'driving': TravelMode('driving', 'Drive', '🚗', 40),
};
const List<String> kModeOrder = ['foot', 'bike', 'scooter', 'transit', 'driving'];

class ModeMetrics {
  final int kcal;
  final double co2saved;
  final String note;
  ModeMetrics(this.kcal, this.co2saved, this.note);
}

ModeMetrics computeMetrics(String key, double km) {
  double kcal, emit;
  String note = '';
  switch (key) {
    case 'foot':
      kcal = km * 55;
      emit = 0;
      break;
    case 'bike':
      kcal = km * 32;
      emit = 0;
      break;
    case 'scooter':
      kcal = km * 8;
      emit = 0.018;
      break;
    case 'transit':
      final walk = (0.12 * km + 0.4).clamp(0.0, 1.8);
      kcal = walk * 60;
      emit = 0.068;
      note = '${walk.toStringAsFixed(1)} km walk to/from stops';
      break;
    default: // driving
      kcal = km * 3;
      emit = kCarCo2;
  }
  final saved = (km * (kCarCo2 - emit));
  return ModeMetrics(kcal.round(), saved < 0 ? 0 : saved, note);
}

double durationFor(String key, double km, {double? driveSec}) {
  if (key == 'driving' && driveSec != null) return driveSec;
  final base = km / kModes[key]!.speedKmh * 3600;
  if (key == 'transit') return base + (km > 2 ? 360 : 180);
  return base;
}

String fmtDur(double seconds) {
  final h = (seconds ~/ 3600);
  final m = ((seconds % 3600) / 60).round();
  return h > 0 ? '$h h $m min' : '$m min';
}

/// A real road path returned by OSRM (mode-agnostic).
class BaseRoute {
  final double km;
  final double driveSec;
  final List<LatLng> points;
  BaseRoute(this.km, this.driveSec, this.points);
}

/// A route presented to the user for a chosen mode.
class RouteOption {
  final String modeKey;
  final String mode;
  final String icon;
  final double km;
  final double durSec;
  final int kcal;
  final double co2saved;
  final String note;
  final List<LatLng> points;
  final String? transitType; // 'bus' | 'train'
  final DateTime? depAt;     // scheduled departure for transit options
  final String? subLabel;    // e.g. boarding stop name
  RouteOption({
    required this.modeKey,
    required this.mode,
    required this.icon,
    required this.km,
    required this.durSec,
    required this.kcal,
    required this.co2saved,
    required this.note,
    required this.points,
    this.transitType,
    this.depAt,
    this.subLabel,
  });

  String get durLabel => fmtDur(durSec);
}

double transitDurSec(String type, double km) {
  final speed = type == 'train' ? 45.0 : (type == 'ferry' ? 25.0 : 24.0);
  return km / speed * 3600 + (km > 2 ? 360 : 180);
}

RouteOption transitOption(BaseRoute b, String type, DateTime depAt, String? boardName) {
  final km = b.km;
  final dur = transitDurSec(type, km);
  final walk = (0.12 * km + 0.4).clamp(0.0, 1.8);
  final kcal = (walk * 60).round();
  final emit = type == 'train' ? 0.041 : (type == 'ferry' ? 0.055 : 0.068);
  final saved = km * (kCarCo2 - emit);
  return RouteOption(
    modeKey: 'transit',
    mode: type == 'train' ? 'Train' : (type == 'ferry' ? 'Ferry' : 'Bus'),
    icon: type == 'train' ? '🚆' : (type == 'ferry' ? '⛴️' : '🚌'),
    km: km,
    durSec: dur,
    kcal: kcal,
    co2saved: saved < 0 ? 0 : saved,
    note: '${walk.toStringAsFixed(1)} km walk to/from stops',
    points: b.points,
    transitType: type,
    depAt: depAt,
    subLabel: boardName,
  );
}

RouteOption optionFromBase(BaseRoute b, String modeKey) {
  final m = kModes[modeKey]!;
  final dur = durationFor(modeKey, b.km, driveSec: b.driveSec);
  final met = computeMetrics(modeKey, b.km);
  return RouteOption(
    modeKey: modeKey,
    mode: m.label,
    icon: m.icon,
    km: b.km,
    durSec: dur,
    kcal: met.kcal,
    co2saved: met.co2saved,
    note: met.note,
    points: b.points,
  );
}

class StopInfo {
  final String name;
  final String type; // 'bus' | 'train'
  final LatLng pos;
  StopInfo(this.name, this.type, this.pos);
}

class Suggestion {
  final String main;
  final String sec;
  final LatLng pos;
  final String type;
  Suggestion(this.main, this.sec, this.pos, this.type);
}

class ScheduledTrip {
  final String dest;
  final String mode;
  final String icon;
  final double km;
  final String dur;
  final int kcal;
  final double co2;
  final DateTime dep;
  final DateTime arr;
  ScheduledTrip({
    required this.dest,
    required this.mode,
    required this.icon,
    required this.km,
    required this.dur,
    required this.kcal,
    required this.co2,
    required this.dep,
    required this.arr,
  });

  Map<String, dynamic> toJson() => {
        'dest': dest, 'mode': mode, 'icon': icon, 'km': km, 'dur': dur,
        'kcal': kcal, 'co2': co2,
        'dep': dep.toIso8601String(), 'arr': arr.toIso8601String(),
      };

  static ScheduledTrip fromJson(Map<String, dynamic> j) => ScheduledTrip(
        dest: j['dest'] ?? 'Trip',
        mode: j['mode'] ?? '',
        icon: j['icon'] ?? '🚗',
        km: (j['km'] ?? 0).toDouble(),
        dur: j['dur'] ?? '',
        kcal: (j['kcal'] ?? 0).toInt(),
        co2: (j['co2'] ?? 0).toDouble(),
        dep: DateTime.parse(j['dep']),
        arr: DateTime.parse(j['arr']),
      );
}
