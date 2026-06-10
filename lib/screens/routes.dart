import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../main.dart';
import '../models.dart';
import 'details.dart';
import 'extras.dart';

class RoutesScreen extends StatelessWidget {
  const RoutesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final from = app.userLoc ?? kBNE;
    final to = app.destLoc;
    final fastest = app.routes.isNotEmpty ? app.routes.first.points : <LatLng>[];

    return Scaffold(
      appBar: AppBar(title: const Text('My Routes'), backgroundColor: Colors.white, leading: menuButton(context), actions: homeActions(context)),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.30,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: to ?? from,
                initialZoom: 12,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.travelly.app',
                ),
                PolylineLayer(polylines: [
                  for (int i = app.routes.length - 1; i >= 1; i--)
                    Polyline(points: app.routes[i].points, color: const Color(0xFF9AA3B2), strokeWidth: 4),
                  if (fastest.isNotEmpty)
                    Polyline(points: fastest, color: brand, strokeWidth: 6),
                ]),
                MarkerLayer(markers: [
                  Marker(point: from, width: 16, height: 16, child: _Dot(Colors.green)),
                  if (to != null) Marker(point: to, width: 16, height: 16, child: _Dot(const Color(0xFFE5343D))),
                ]),
              ],
            ),
          ),
          Expanded(
            child: Container(
              transform: Matrix4.translationValues(0, -18, 0),
              decoration: const BoxDecoration(
                color: Color(0xFFF3F4F8),
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('${app.userLabel} → ${app.destName}',
                      style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
                  const SizedBox(height: 10),
                  _modeSelector(context, app),
                  const SizedBox(height: 6),
                  const Text('Tap a route to see details, then start or schedule it.',
                      style: TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                  const SizedBox(height: 10),
                  ...app.routes.asMap().entries.map((e) => _routeCard(context, app, e.key, e.value)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeSelector(BuildContext context, AppState app) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: kModeOrder.map((k) {
          final m = kModes[k]!;
          final on = app.mode == k;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: on,
              label: Text('${m.icon} ${k == 'driving' ? 'Drive' : (k == 'transit' ? 'Transit' : m.label)}'),
              selectedColor: const Color(0xFFE7EDFF),
              labelStyle: TextStyle(color: on ? brand : const Color(0xFF6B7280), fontWeight: FontWeight.w600),
              onSelected: (_) => app.setMode(k),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _routeCard(BuildContext context, AppState app, int i, RouteOption r) {
    final t = app.timesFor(r);
    final eco = r.co2saved > 0
        ? '🌱 ${r.co2saved.toStringAsFixed(1)} kg CO₂ saved'
        : '🚗 ${(r.km * kCarCo2).toStringAsFixed(1)} kg CO₂';
    return InkWell(
      onTap: () {
        app.selected = i;
        Navigator.push(context, MaterialPageRoute(builder: (_) => TripDetailsScreen(index: i)));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 11),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: i == app.selected ? brand : const Color(0xFFE7E8EE),
                width: i == app.selected ? 2 : 1.5)),
        child: Row(children: [
          Text(r.icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 13),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.durLabel, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(_subtitle(r, t), style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
              if (r.subLabel != null)
                Text('from ${r.subLabel}',
                    style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Row(children: [
                _chip(eco, const Color(0xFFE9F9EF), const Color(0xFF16A34A)),
                const SizedBox(width: 6),
                _chip('${r.kcal} kcal', const Color(0xFFEEF2FF), brand),
              ]),
            ]),
          ),
          const Icon(Icons.chevron_right, color: Color(0xFFC2C6D2)),
        ]),
      ),
    );
  }

  String _subtitle(RouteOption r, ({DateTime dep, DateTime arr}) t) {
    if (r.depAt != null) {
      final mins = r.depAt!.difference(DateTime.now()).inMinutes;
      final inTxt = mins >= 0 ? 'Departs in $mins min' : 'Departs ${hhmm(t.dep)}';
      return '$inTxt · ${hhmm(t.dep)} → ${hhmm(t.arr)}';
    }
    return 'Depart ${hhmm(t.dep)} · Arrive ${hhmm(t.arr)}';
  }

  Widget _chip(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot(this.color);
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
      );
}
