import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'models.dart';
import 'services.dart';
import 'screens/plan.dart';
import 'screens/extras.dart';

const brand = Color(0xFF1769FF);
final LatLng kBNE = LatLng(-27.4705, 153.0260);

void main() => runApp(
      ChangeNotifierProvider(create: (_) => AppState()..init(), child: const TravellyApp()),
    );

class TravellyApp extends StatelessWidget {
  const TravellyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Travelly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: brand, primary: brand),
        scaffoldBackgroundColor: const Color(0xFFF3F4F8),
        fontFamily: 'Roboto',
      ),
      home: const HomeScreen(),
    );
  }
}

/// ---------------- App state ----------------
class AppState extends ChangeNotifier {
  LatLng? userLoc;
  String userLabel = 'Locating…';
  String? wxTemp;
  String wxIcon = '⛅';

  LatLng? destLoc;
  String destName = '';

  String timing = 'now'; // now | depart | arrive
  DateTime? tripWhen;

  String mode = 'driving';
  List<BaseRoute> baseRoutes = [];
  List<RouteOption> routes = [];
  int selected = 0;
  int scootAvail = 0;
  StopInfo? boardBus, boardTrain, destBus, destTrain;

  List<ScheduledTrip> scheduled = [];

  Future<void> init() async {
    await _loadScheduled();
    await locate();
  }

  Future<void> locate() async {
    final p = await Services.currentPosition();
    if (p != null) {
      userLoc = p;
      notifyListeners();
      userLabel = await Services.reverseGeocode(p);
      final w = await Services.weather(p);
      if (w != null) {
        wxTemp = '${(w['temperature_2m'] as num).round()}°';
        wxIcon = wxEmoji((w['weather_code'] as num?)?.toInt());
      }
      notifyListeners();
    } else {
      userLabel = 'Enable GPS';
      final w = await Services.weather(kBNE);
      if (w != null) {
        wxTemp = '${(w['temperature_2m'] as num).round()}°';
        wxIcon = wxEmoji((w['weather_code'] as num?)?.toInt());
      }
      notifyListeners();
    }
  }

  void setDest(LatLng p, String name) {
    destLoc = p;
    destName = name;
    notifyListeners();
  }

  void setTiming(String t, DateTime? when) {
    timing = t;
    tripWhen = when;
    notifyListeners();
  }

  void setMode(String m) {
    mode = m;
    _rebuild();
  }

  Future<void> findRoutes() async {
    final from = userLoc ?? kBNE;
    final to = destLoc!;
    scootAvail = 2 + (DateTime.now().millisecondsSinceEpoch % 6);
    baseRoutes = await Services.routes(from, to);
    if (baseRoutes.isEmpty) {
      final dist = const Distance();
      final km = dist.as(LengthUnit.Kilometer, from, to) * 1.3;
      baseRoutes = [BaseRoute(km, km / 40 * 3600, [from, to])];
    }
    boardBus = boardTrain = destBus = destTrain = null;
    _fetchTransitStops(from, to);
    _rebuild();
  }

  void _rebuild() {
    if (mode == 'transit') {
      routes = _buildTransit();
    } else {
      routes = baseRoutes.map((b) => optionFromBase(b, mode)).toList()
        ..sort((a, b) => a.durSec.compareTo(b.durSec));
    }
    selected = 0;
    notifyListeners();
  }

  Future<void> _fetchTransitStops(LatLng from, LatLng to) async {
    final o = await Services.nearestByType(from);
    final d = await Services.nearestByType(to);
    boardBus = o.bus;
    boardTrain = o.train;
    destBus = d.bus;
    destTrain = d.train;
    if (mode == 'transit') _rebuild();
  }

  bool get trainViable => boardTrain != null && destTrain != null;

  /// Several upcoming bus/train options, departures spread across the next hour.
  List<RouteOption> _buildTransit() {
    if (baseRoutes.isEmpty) return [];
    final DateTime base = (timing == 'depart' && tripWhen != null)
        ? tripWhen!
        : (timing == 'arrive' && tripWhen != null)
            ? tripWhen!.subtract(const Duration(minutes: 60))
            : DateTime.now();
    const offsets = [8, 20, 32, 44, 56];
    final out = <RouteOption>[];
    for (var i = 0; i < offsets.length; i++) {
      final type = (trainViable && i.isOdd) ? 'train' : 'bus';
      final b = baseRoutes[i % baseRoutes.length];
      final boardName = type == 'train' ? boardTrain?.name : boardBus?.name;
      out.add(transitOption(b, type, base.add(Duration(minutes: offsets[i])), boardName));
    }
    out.sort((a, b) => a.depAt!.compareTo(b.depAt!));
    return out;
  }

  /// Departure/arrival for a route, honouring per-option transit departure time.
  ({DateTime dep, DateTime arr}) timesFor(RouteOption r) {
    if (r.depAt != null) {
      return (dep: r.depAt!, arr: r.depAt!.add(Duration(seconds: r.durSec.round())));
    }
    return computeTimes(r.durSec);
  }

  /// depart/arrive times for a route given current timing settings
  ({DateTime dep, DateTime arr}) computeTimes(double durSec) {
    final now = DateTime.now();
    final d = Duration(seconds: durSec.round());
    if (timing == 'arrive' && tripWhen != null) {
      return (dep: tripWhen!.subtract(d), arr: tripWhen!);
    } else if (timing == 'depart' && tripWhen != null) {
      return (dep: tripWhen!, arr: tripWhen!.add(d));
    }
    return (dep: now, arr: now.add(d));
  }

  Future<void> _loadScheduled() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('travelly_sched');
    if (raw != null) {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      scheduled = list.map(ScheduledTrip.fromJson).toList();
    }
  }

  Future<void> addScheduled(ScheduledTrip t) async {
    scheduled.add(t);
    scheduled.sort((a, b) => a.dep.compareTo(b.dep));
    await _saveScheduled();
    notifyListeners();
  }

  Future<void> removeScheduled(int i) async {
    scheduled.removeAt(i);
    await _saveScheduled();
    notifyListeners();
  }

  Future<void> _saveScheduled() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'travelly_sched', jsonEncode(scheduled.map((e) => e.toJson()).toList()));
  }
}

String hhmm(DateTime d) => DateFormat('h:mm a').format(d);
String fmtDateTime(DateTime d) {
  final today = DateTime.now();
  final same = d.year == today.year && d.month == today.month && d.day == today.day;
  return (same ? 'Today' : DateFormat('EEE, d MMM').format(d)) + ' · ' + hhmm(d);
}

/// ---------------- Home ----------------
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final center = app.userLoc ?? kBNE;
    return Scaffold(
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(initialCenter: center, initialZoom: 14),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.travelly.app',
              ),
              if (app.userLoc != null)
                MarkerLayer(markers: [
                  Marker(
                    point: app.userLoc!,
                    width: 22,
                    height: 22,
                    child: const _UserDot(),
                  )
                ]),
            ],
          ),
          // Top HUD
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(
                    builder: (ctx) => _FabIcon(
                      icon: Icons.menu,
                      onTap: () => Scaffold.of(ctx).openDrawer(),
                    ),
                  ),
                  const Spacer(),
                  _InfoCard(icon: app.wxIcon, temp: app.wxTemp ?? '—', place: app.userLabel),
                ],
              ),
            ),
          ),
          // Locate button
          Positioned(
            right: 14,
            bottom: MediaQuery.of(context).size.height * 0.34,
            child: _FabIcon(icon: Icons.my_location, onTap: () => app.locate()),
          ),
          // Bottom sheet
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42, height: 5, margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD7D9E2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const Text('Where to Today?',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  const Text('Plan a sustainable route and earn rewards.',
                      style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const PlanScreen())),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F2F7),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(children: [
                        Icon(Icons.search, color: Color(0xFF6B7280)),
                        SizedBox(width: 10),
                        Text('Search destination…',
                            style: TextStyle(color: Color(0xFF6B7280), fontSize: 15)),
                      ]),
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
}

class _UserDot extends StatelessWidget {
  const _UserDot();
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: brand,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [BoxShadow(color: brand.withOpacity(.4), blurRadius: 4)],
        ),
      );
}

class _InfoCard extends StatelessWidget {
  final String icon, temp, place;
  const _InfoCard({required this.icon, required this.temp, required this.place});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.96),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(temp, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          Container(
              width: 1, height: 22,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: const Color(0xFFE7E8EE)),
          const Icon(Icons.place, size: 15, color: brand),
          const SizedBox(width: 3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Near',
                    style: TextStyle(fontSize: 10, color: Color(0xFF6B7280), height: 1)),
                Text(place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, height: 1.15)),
              ],
            ),
          ),
        ]),
      );
}

class _FabIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _FabIcon({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white.withOpacity(.95),
        borderRadius: BorderRadius.circular(14),
        elevation: 3,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Icon(icon, color: const Color(0xFF1A1C22))),
        ),
      );
}
