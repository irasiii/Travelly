import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../db.dart';
import '../models.dart';
import '../services.dart';
import 'extras.dart';

class _Step {
  final String icon, title, detail;
  final Color color;
  _Step(this.icon, this.color, this.title, this.detail);
}

class TripDetailsScreen extends StatefulWidget {
  final int index;
  const TripDetailsScreen({super.key, required this.index});
  @override
  State<TripDetailsScreen> createState() => _TripDetailsScreenState();
}

class _TripDetailsScreenState extends State<TripDetailsScreen> {
  List<_Step>? _steps;
  List<Marker> _stopMarkers = [];
  bool _loading = false;

  late int idx;
  RouteOption get r => context.read<AppState>().routes[idx];

  @override
  void initState() {
    super.initState();
    idx = widget.index;
    _buildSteps();
  }

  void _go(int delta) {
    final n = context.read<AppState>().routes.length;
    final ni = (idx + delta).clamp(0, n - 1);
    if (ni != idx) {
      setState(() { idx = ni; _steps = null; _stopMarkers = []; });
      context.read<AppState>().selected = idx;
      _buildSteps();
    }
  }

  Widget _routeNav() {
    final n = context.read<AppState>().routes.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        TextButton.icon(
          onPressed: idx > 0 ? () => _go(-1) : null,
          icon: const Icon(Icons.chevron_left), label: const Text('Prev')),
        Text('Route ${idx + 1} of $n',
            style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF6B7280))),
        TextButton(
          onPressed: idx < n - 1 ? () => _go(1) : null,
          child: const Row(mainAxisSize: MainAxisSize.min,
              children: [Text('Next'), Icon(Icons.chevron_right)])),
      ]),
    );
  }

  Future<void> _buildSteps() async {
    final app = context.read<AppState>();
    if (r.modeKey != 'transit') {
      final t = app.timesFor(r);
      setState(() => _steps = [
            _Step('🟢', Colors.green, 'Depart ${app.userLabel}', hhmm(t.dep)),
            _Step(r.icon, brand, '${r.mode} · ${r.km.toStringAsFixed(1)} km', r.durLabel),
            _Step('🔴', const Color(0xFFE5343D), 'Arrive ${app.destName}', hhmm(t.arr)),
          ]);
      return;
    }
    setState(() => _loading = true);
    final from = app.userLoc ?? kBNE;
    final to = app.destLoc!;
    final type = r.transitType ?? 'bus';
    StopInfo? board = type == 'train' ? app.boardTrain : app.boardBus;
    StopInfo? alight = type == 'train' ? app.destTrain : app.destBus;
    board ??= await Services.nearestStop(from);
    alight ??= await Services.nearestStop(to);
    final dist = const Distance();
    final t = app.timesFor(r);
    var cur = t.dep;
    final w1 = (board != null ? dist.as(LengthUnit.Kilometer, from, board.pos) * 1.25 : 0.4).clamp(0.05, 50.0);
    final w2 = (alight != null ? dist.as(LengthUnit.Kilometer, alight.pos, to) * 1.25 : 0.4).clamp(0.05, 50.0);
    final w1sec = w1 / 5 * 3600, w2sec = w2 / 5 * 3600;
    final rideSec = (r.durSec - w1sec - w2sec).clamp(120, 1e9).toDouble();
    final steps = <_Step>[];
    steps.add(_Step('🚶', const Color(0xFF16A34A), 'Walk to ${board?.name ?? 'nearest stop'}',
        '${hhmm(cur)} · ${w1.toStringAsFixed(1)} km · ${(w1sec / 60).round()} min'));
    cur = cur.add(Duration(seconds: w1sec.round()));
    final boardTime = hhmm(cur);
    final isTrain = type == 'train';
    steps.add(_Step(isTrain ? '🚆' : '🚌', isTrain ? brand : const Color(0xFFF59E0B),
        '${isTrain ? 'Train' : 'Bus'}  ${board?.name ?? 'Board'} → ${alight?.name ?? 'Alight'}',
        'Board $boardTime · ${(rideSec / 60).round()} min ride'));
    cur = cur.add(Duration(seconds: rideSec.round()));
    steps.add(_Step('🚶', const Color(0xFF16A34A), 'Walk to ${app.destName}',
        '${hhmm(cur)} · ${w2.toStringAsFixed(1)} km · ${(w2sec / 60).round()} min'));
    cur = cur.add(Duration(seconds: w2sec.round()));
    steps.add(_Step('🏁', const Color(0xFFE5343D), 'Arrive ${app.destName}', hhmm(cur)));

    final markers = <Marker>[];
    if (board != null) markers.add(_stopMarker(board));
    if (alight != null) markers.add(_stopMarker(alight));
    if (mounted) setState(() { _steps = steps; _stopMarkers = markers; _loading = false; });
  }

  Marker _stopMarker(StopInfo s) => Marker(
        point: s.pos, width: 28, height: 28,
        child: Text(s.type == 'train' ? '🚉' : '🚏', style: const TextStyle(fontSize: 20)),
      );

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = app.timesFor(r);
    final pts = r.points;
    return Scaffold(
      appBar: AppBar(title: const Text('Trip Details'), backgroundColor: Colors.white, actions: menuActions(context)),
      drawer: const AppDrawer(),
      body: Column(children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.28,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: pts.isNotEmpty ? pts[pts.length ~/ 2] : kBNE,
              initialZoom: 12,
            ),
            children: [
              TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.travelly.app'),
              PolylineLayer(polylines: [Polyline(points: pts, color: brand, strokeWidth: 6)]),
              MarkerLayer(markers: [
                if (pts.isNotEmpty) Marker(point: pts.first, width: 16, height: 16, child: _dot(Colors.green)),
                if (pts.isNotEmpty) Marker(point: pts.last, width: 16, height: 16, child: _dot(const Color(0xFFE5343D))),
                ..._stopMarkers,
              ]),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _routeNav(),
              _card(Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.durLabel, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
                  Text('${r.mode} · ${r.km.toStringAsFixed(1)} km',
                      style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
                ])),
                Text(r.icon, style: const TextStyle(fontSize: 34)),
              ])),
              _card(Column(children: [
                _row(Icons.rocket_launch, 'Depart', fmtDateTime(t.dep)),
                _row(Icons.flag, 'Arrive', fmtDateTime(t.arr)),
                _row(Icons.local_fire_department, 'Calories burned', '${r.kcal} kcal'),
                _row(Icons.eco, 'Carbon impact',
                    r.co2saved > 0 ? '${r.co2saved.toStringAsFixed(2)} kg saved vs car' : '${(r.km * kCarCo2).toStringAsFixed(2)} kg emitted'),
                if (r.modeKey == 'transit')
                  Padding(padding: const EdgeInsets.only(top: 8),
                      child: Align(alignment: Alignment.centerLeft, child: Text('🚶 ${r.note} — you still burn calories on public transport!',
                          style: const TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.w700, fontSize: 12)))),
                if (r.modeKey == 'scooter')
                  Padding(padding: const EdgeInsets.only(top: 8),
                      child: Align(alignment: Alignment.centerLeft, child: Text('🛴 ${app.scootAvail} e-scooters available near you now — zero tailpipe CO₂.',
                          style: const TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.w700, fontSize: 12)))),
              ])),
              const Padding(padding: EdgeInsets.fromLTRB(2, 4, 2, 8),
                  child: Text('TRIP STEPS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF6B7280), letterSpacing: .5))),
              if (_loading) const Padding(padding: EdgeInsets.all(12), child: Text('🚏 Finding nearby stops & stations…', style: TextStyle(color: Color(0xFF6B7280)))),
              if (_steps != null) ..._steps!.map(_stepTile),
              if (r.modeKey == 'transit' && _steps != null)
                const Padding(padding: EdgeInsets.only(top: 6),
                    child: Text('🚏 Stops & stations from OpenStreetMap. Exact route number and live timetable need a GTFS feed.',
                        style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)))),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ActiveTripScreen(index: idx))),
                style: FilledButton.styleFrom(backgroundColor: brand, minimumSize: const Size.fromHeight(52)),
                child: const Text('▶ Start Trip Now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () => _openSchedule(context, app),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A), minimumSize: const Size.fromHeight(52)),
                child: const Text('📅 Schedule Trip', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.list),
                label: const Text('Back to all routes'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Future<void> _openSchedule(BuildContext context, AppState app) async {
    String kind = app.timing == 'arrive' ? 'arrive' : 'depart';
    DateTime base = app.tripWhen ?? DateTime.now().add(const Duration(hours: 1));
    DateTime? date = base;
    TimeOfDay? time = TimeOfDay.fromDateTime(base);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        DateTime? dt() => (date != null && time != null)
            ? DateTime(date!.year, date!.month, date!.day, time!.hour, time!.minute)
            : null;
        final picked = dt();
        DateTime? dep, arr;
        if (picked != null) {
          if (kind == 'arrive') { arr = picked; dep = picked.subtract(Duration(seconds: r.durSec.round())); }
          else { dep = picked; arr = picked.add(Duration(seconds: r.durSec.round())); }
        }
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Schedule Trip', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ToggleButtons(
              isSelected: [kind == 'depart', kind == 'arrive'],
              borderRadius: BorderRadius.circular(10),
              onPressed: (i) => setSheet(() => kind = i == 0 ? 'depart' : 'arrive'),
              children: const [Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Depart at')),
                Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Arrive by'))],
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () async {
                  final d = await showDatePicker(context: ctx, initialDate: date ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (d != null) setSheet(() => date = d);
                },
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(date == null ? 'Date' : DateFormat('EEE, d MMM').format(date!)),
              )),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(
                onPressed: () async {
                  final tt = await showTimePicker(context: ctx, initialTime: time ?? TimeOfDay.now());
                  if (tt != null) setSheet(() => time = tt);
                },
                icon: const Icon(Icons.access_time, size: 18),
                label: Text(time == null ? 'Time' : time!.format(ctx)),
              )),
            ]),
            const SizedBox(height: 10),
            if (dep != null && arr != null)
              Text('🚀 Depart ${fmtDateTime(dep)}  →  🎯 Arrive ${fmtDateTime(arr)}',
                  style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () async {
                if (dep == null || arr == null) return;
                await app.addScheduled(ScheduledTrip(
                  dest: app.destName, mode: r.mode, icon: r.icon, km: r.km, dur: r.durLabel,
                  kcal: r.kcal, co2: r.co2saved, dep: dep!, arr: arr!));
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✓ Scheduled — depart ${fmtDateTime(dep!)}')));
                }
              },
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A), minimumSize: const Size.fromHeight(50)),
              child: const Text('✓ Confirm Schedule', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
        );
      }),
    );
  }

  Widget _stepTile(_Step s) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 34, height: 34, alignment: Alignment.center,
              decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(10)),
              child: Text(s.icon, style: const TextStyle(fontSize: 16))),
          const SizedBox(width: 13),
          Expanded(child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 2),
              Text(s.detail, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
            ]),
          )),
        ]),
      );

  Widget _card(Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: child,
      );

  Widget _row(IconData ic, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          SizedBox(width: 26, child: Icon(ic, size: 18, color: const Color(0xFF6B7280))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            Text(v, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ])),
        ]),
      );

  Widget _dot(Color c) => Container(decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)));
}

/// ---------------- Active trip ----------------
class ActiveTripScreen extends StatefulWidget {
  final int index;
  const ActiveTripScreen({super.key, required this.index});
  @override
  State<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> {
  late RouteOption r;
  final MapController _map = MapController();
  StreamSubscription? _sub;
  Timer? _timer;
  int sec = 0;
  double dist = 0, kcal = 0, co2 = 0;
  LatLng? _last, _cur;
  final List<LatLng> _trail = [];
  String _status = 'Waiting for GPS…';

  @override
  void initState() {
    super.initState();
    r = context.read<AppState>().routes[widget.index];
    _start();
  }

  void _start() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => sec++);
    });
    final perKm = r.km > 0 ? r.kcal / r.km : 50.0;
    final perKmCo2 = r.km > 0 ? r.co2saved / r.km : kCarCo2;
    _sub = Services.positionStream().listen((p) {
      final pt = LatLng(p.latitude, p.longitude);
      setState(() {
        _status = 'Tracking live';
        if (_last != null) {
          final d = const Distance().as(LengthUnit.Kilometer, _last!, pt);
          // ignore GPS jitter/teleports
          if (d.isFinite && d < 0.5) {
            dist += d;
            kcal += perKm * d;
            co2 += perKmCo2 * d;
          }
        }
        _last = pt;
        _cur = pt;
        _trail.add(pt);
      });
      try {
        _map.move(pt, 16);
      } catch (_) {}
    }, onError: (_) {
      if (mounted) setState(() => _status = 'GPS unavailable — enable location');
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pts = r.points;
    final center = _cur ?? (pts.isNotEmpty ? pts.first : kBNE);
    final live = _status == 'Tracking live';
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(initialCenter: center, initialZoom: 15),
          children: [
            TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.travelly.app'),
            PolylineLayer(polylines: [
              Polyline(points: pts, color: brand.withOpacity(.30), strokeWidth: 6),
              if (_trail.length > 1) Polyline(points: _trail, color: brand, strokeWidth: 6),
            ]),
            if (_cur != null)
              MarkerLayer(markers: [Marker(point: _cur!, width: 22, height: 22, child: _liveDot())]),
          ],
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.white.withOpacity(.95), borderRadius: BorderRadius.circular(16)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, size: 10, color: live ? const Color(0xFF16A34A) : const Color(0xFFE5343D)),
                  const SizedBox(width: 7),
                  Text(_status, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
              ),
            ),
          ),
        ),
        Positioned(
          right: 14,
          bottom: MediaQuery.of(context).size.height * 0.30,
          child: FloatingActionButton.small(
            heroTag: 'recenter',
            backgroundColor: Colors.white,
            foregroundColor: brand,
            onPressed: () { if (_cur != null) _map.move(_cur!, 16); },
            child: const Icon(Icons.my_location),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 26),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 42, height: 5, margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: const Color(0xFFD7D9E2), borderRadius: BorderRadius.circular(3))),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(r.icon), const SizedBox(width: 6),
                Text(r.mode, style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _stat('${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}', 'Time'),
                _stat('${dist.toStringAsFixed(2)} km', 'Distance'),
                _stat('${kcal.round()}', 'Kcal'),
                _stat(co2.toStringAsFixed(2), 'kg CO₂'),
              ]),
              const SizedBox(height: 8),
              const Text('Live distance is measured from your real GPS movement.',
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  await Db.addTrip({
                    'mode': r.mode,
                    'icon': r.icon,
                    'km': double.parse(dist.toStringAsFixed(2)),
                    'durSec': sec,
                    'kcal': kcal.round(),
                    'co2': double.parse(co2.toStringAsFixed(2)),
                    'date': DateTime.now().toIso8601String(),
                  });
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Trip saved to your history 🌱')));
                  Navigator.popUntil(context, (route) => route.isFirst);
                },
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5343D), minimumSize: const Size.fromHeight(50)),
                child: const Text('Finish Trip', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _liveDot() => Container(
        decoration: BoxDecoration(
          color: brand,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [BoxShadow(color: brand.withOpacity(.4), blurRadius: 6)],
        ),
      );

  Widget _stat(String v, String l) => Column(children: [
        Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        Text(l, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
      ]);
}
