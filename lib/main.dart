import 'dart:async';
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
import 'screens/auth.dart';
import 'db.dart';

const brand = Color(0xFF1769FF);
final LatLng kBNE = LatLng(-27.4705, 153.0260);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Db.init();
  runApp(
    ChangeNotifierProvider(create: (_) => AppState()..init(), child: const TravellyApp()),
  );
}

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
      home: const AuthGate(),
    );
  }
}

/// ---------------- App state ----------------
class AppState extends ChangeNotifier {
  bool loggedIn = Db.isLoggedIn;
  String get userName => Db.currentName;
  void refreshAuth() {
    loggedIn = Db.isLoggedIn;
    notifyListeners();
  }

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
  StopInfo? boardBus, boardTrain, destBus, destTrain, boardFerry, destFerry;

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
        wxTemp = '${(w['temperature_2m'] as num).round()}°C';
        wxIcon = wxEmoji((w['weather_code'] as num?)?.toInt());
      }
      notifyListeners();
    } else {
      userLabel = 'Enable GPS';
      final w = await Services.weather(kBNE);
      if (w != null) {
        wxTemp = '${(w['temperature_2m'] as num).round()}°C';
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

  /// Change timing on the routes screen and recompute departure/arrival times.
  void updateTiming(String t, DateTime? when) {
    timing = t;
    tripWhen = when;
    if (baseRoutes.isNotEmpty) {
      _rebuild();
    } else {
      notifyListeners();
    }
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
    boardFerry = o.ferry;
    destBus = d.bus;
    destTrain = d.train;
    destFerry = d.ferry;
    if (mode == 'transit') _rebuild();
  }

  bool get trainViable => boardTrain != null && destTrain != null;
  bool get ferryViable => boardFerry != null && destFerry != null;

  /// Several upcoming bus/train options, departures spread across the next hour.
  String? _boardNameFor(String type) {
    if (type == 'train') return boardTrain?.name;
    if (type == 'ferry') return boardFerry?.name;
    return boardBus?.name;
  }

  List<RouteOption> _buildTransit() {
    if (baseRoutes.isEmpty) return [];
    // Available public-transport types near both ends (bus always, train/ferry if found).
    final types = <String>['bus'];
    if (trainViable) types.add('train');
    if (ferryViable) types.add('ferry');

    // Offsets spread departures (or arrivals) across the next ~hour.
    const offsets = [6, 16, 28, 40, 52];
    final arriveMode = timing == 'arrive' && tripWhen != null;
    final departBase = (timing == 'depart' && tripWhen != null) ? tripWhen! : DateTime.now();

    final out = <RouteOption>[];
    for (var i = 0; i < offsets.length; i++) {
      final type = types[i % types.length];
      final b = baseRoutes[i % baseRoutes.length];
      final dur = transitDurSec(type, b.km);
      DateTime depAt;
      if (arriveMode) {
        // Work backwards: arrive a little before the target, depart = arrival - duration.
        final arriveBy = tripWhen!.subtract(Duration(minutes: i * 8));
        depAt = arriveBy.subtract(Duration(seconds: dur.round()));
      } else {
        depAt = departBase.add(Duration(minutes: offsets[i]));
      }
      out.add(transitOption(b, type, depAt, _boardNameFor(type)));
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
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return app.loggedIn ? const HomeScreen() : const LoginScreen();
  }
}

class ClockText extends StatefulWidget {
  const ClockText({super.key});
  @override
  State<ClockText> createState() => _ClockTextState();
}

class _ClockTextState extends State<ClockText> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
        DateFormat('h:mm:ss a').format(DateTime.now()),
        style: const TextStyle(fontWeight: FontWeight.w700, color: brand, fontSize: 13),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MapController _map = MapController();
  bool _centered = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // recenter on the user the first time GPS resolves
    if (app.userLoc != null && !_centered) {
      _centered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _map.move(app.userLoc!, 15);
        } catch (_) {}
      });
    }
    final center = app.userLoc ?? kBNE;
    return Scaffold(
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(initialCenter: center, initialZoom: 13),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.travelly.app',
              ),
              if (app.userLoc != null)
                MarkerLayer(markers: [
                  Marker(point: app.userLoc!, width: 24, height: 24, child: const _UserDot()),
                ]),
            ],
          ),
          // Top bar: menu (left) + weather & place chips (right, stacked)
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _WeatherChip(icon: app.wxIcon, temp: app.wxTemp),
                      const SizedBox(height: 6),
                      if (app.userLabel.isNotEmpty &&
                          app.userLabel != 'Locating…')
                        _PlaceChip(place: app.userLabel),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Locate button
          Positioned(
            right: 14,
            bottom: MediaQuery.of(context).size.height * 0.34,
            child: _FabIcon(
              icon: Icons.my_location,
              onTap: () async {
                await app.locate();
                if (app.userLoc != null) {
                  try {
                    _map.move(app.userLoc!, 16);
                  } catch (_) {}
                }
              },
            ),
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
                      width: 42,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD7D9E2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text('Hi ${app.userName.split(' ').first} 👋',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      ),
                      const ClockText(),
                    ],
                  ),
                  const SizedBox(height: 3),
                  const Text('Where to today? Plan a sustainable route.',
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

class _WeatherChip extends StatelessWidget {
  final String icon;
  final String? temp;
  const _WeatherChip({required this.icon, required this.temp});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.96),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 7),
          Text(temp ?? '—',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
      );
}

class _PlaceChip extends StatelessWidget {
  final String place;
  const _PlaceChip({required this.place});
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 180),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.96),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.place, size: 14, color: brand),
          const SizedBox(width: 4),
          Flexible(
            child: Text(place,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
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
