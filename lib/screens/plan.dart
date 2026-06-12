import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../main.dart';
import '../models.dart';
import '../services.dart';
import '../db.dart';
import 'routes.dart';
import 'extras.dart';

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});
  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  final _cur = TextEditingController();
  final _dest = TextEditingController();
  List<Suggestion> _sug = [];
  String _active = ''; // which field is showing suggestions
  String _timing = 'now';
  DateTime? _date;
  TimeOfDay? _time;
  bool _busy = false;
  final _destFocus = FocusNode();
  List<Map> _recent = [];

  @override
  void initState() {
    super.initState();
    _prefillCurrent();
    _recent = Db.recentDests();
    _destFocus.addListener(() {
      if (_destFocus.hasFocus && _dest.text.trim().isEmpty && _recent.isNotEmpty) {
        setState(() => _active = 'recent');
      }
    });
  }

  @override
  void dispose() {
    _destFocus.dispose();
    super.dispose();
  }

  void _prefillCurrent() {
    final app = context.read<AppState>();
    if (app.userLoc != null) {
      final lbl = (app.userLabel != 'Locating…' && app.userLabel != 'Enable GPS')
          ? app.userLabel
          : 'My location';
      _cur.text = '📍 $lbl';
    } else {
      _cur.text = '📍 Locating you…';
      app.locate().then((_) {
        if (!mounted) return;
        setState(() {
          _cur.text = app.userLoc != null ? '📍 ${app.userLabel}' : '';
        });
      });
    }
  }

  Future<void> _search(String field, String q) async {
    final app = context.read<AppState>();
    final res = await Services.geocode(q, near: app.userLoc);
    if (mounted) setState(() { _sug = res; _active = field; });
  }

  void _pick(Suggestion s) async {
    final app = context.read<AppState>();
    if (_active == 'dest') {
      final name = s.main + (s.sec.isNotEmpty ? ', ${s.sec.split(',').first}' : '');
      _dest.text = name;
      app.setDest(s.pos, s.main);
      await Db.addRecentDest(s.main, s.pos.latitude, s.pos.longitude);
      _recent = Db.recentDests();
      if (!mounted) return;
      setState(() { _sug = []; _active = ''; });
      _destFocus.unfocus();
      _find();
    } else {
      _cur.text = s.main;
      app.userLoc = s.pos;
      setState(() { _sug = []; _active = ''; });
    }
  }

  void _pickRecent(Map m) {
    final app = context.read<AppState>();
    final pos = LatLng((m['lat'] as num).toDouble(), (m['lon'] as num).toDouble());
    final name = '${m['name']}';
    _dest.text = name;
    app.setDest(pos, name);
    setState(() { _active = ''; _sug = []; });
    _destFocus.unfocus();
    _find();
  }

  Future<void> _find() async {
    final app = context.read<AppState>();
    final destText = _dest.text.trim();
    if (destText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a destination first')));
      return;
    }
    setState(() => _busy = true);
    if (app.userLoc == null) {
      await app.locate();
    }
    if (app.destLoc == null) {
      final p = await Services.geocodeOne(destText, near: app.userLoc);
      if (p == null) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not locate that destination')));
        return;
      }
      app.setDest(p, destText);
    }
    DateTime? when;
    if (_timing != 'now' && _date != null && _time != null) {
      when = DateTime(_date!.year, _date!.month, _date!.day, _time!.hour, _time!.minute);
    }
    app.setTiming(_timing, when);
    await app.findRoutes();
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const RoutesScreen()));
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
        context: context, initialTime: _time ?? TimeOfDay.now());
    if (t != null) setState(() => _time = t);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan Journey'), backgroundColor: Colors.white, leading: menuButton(context), actions: homeActions(context)),
      drawer: const AppDrawer(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field(_cur, 'Current location', brand, 'cur'),
          if (_active == 'cur') _suggestions(),
          const SizedBox(height: 8),
          _field(_dest, 'Destination — street, brand or venue (e.g. Aldi, Sunnybank Plaza)',
              const Color(0xFFE5343D), 'dest'),
          if (_active == 'dest') _suggestions(),
          if (_active == 'recent') _recentList(),
          const SizedBox(height: 14),
          _segment(),
          if (_timing != 'now') ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _dtButton(
                  _date == null ? 'Select date' : DateFormat('EEE, d MMM').format(_date!),
                  Icons.calendar_today, _pickDate)),
              const SizedBox(width: 10),
              Expanded(child: _dtButton(
                  _time == null ? 'Select time' : _time!.format(context),
                  Icons.access_time, _pickTime)),
            ]),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _find,
            style: FilledButton.styleFrom(
                backgroundColor: brand, minimumSize: const Size.fromHeight(52)),
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Find Routes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, Color dot, String field) {
    return Container(
      decoration: BoxDecoration(
          color: const Color(0xFFF1F2F7), borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        Container(width: 14, height: 14, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 11),
        Expanded(
          child: TextField(
            controller: c,
            focusNode: field == 'dest' ? _destFocus : null,
            decoration: InputDecoration(hintText: hint, border: InputBorder.none),
            onChanged: (v) {
              if (field == 'dest') context.read<AppState>().destLoc = null;
              if (v.replaceAll('📍', '').trim().length >= 2) {
                _search(field, v.replaceAll('📍', '').trim());
              } else {
                setState(() {
                  _sug = [];
                  _active = (field == 'dest' && _recent.isNotEmpty) ? 'recent' : '';
                });
              }
            },
          ),
        ),
      ]),
    );
  }

  Widget _suggestions() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12)]),
      child: Column(
        children: _sug.map((s) => ListTile(
              dense: true,
              leading: const Icon(Icons.place_outlined, size: 20),
              title: Text(s.main, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: s.sec.isNotEmpty ? Text(s.sec, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
              trailing: _distWidget(s.pos),
              onTap: () => _pick(s),
            )).toList(),
      ),
    );
  }

  Widget? _distWidget(LatLng pos) {
    final u = context.read<AppState>().userLoc;
    if (u == null) return null;
    final km = const Distance().as(LengthUnit.Kilometer, u, pos);
    final label = km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';
    return Text(label, style: const TextStyle(color: brand, fontWeight: FontWeight.w700, fontSize: 12));
  }

  Widget _recentList() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12)]),
      child: Column(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 10, 14, 2),
          child: Align(alignment: Alignment.centerLeft,
              child: Text('RECENT DESTINATIONS',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF6B7280), letterSpacing: .5))),
        ),
        ..._recent.map((m) {
          final pos = LatLng((m['lat'] as num).toDouble(), (m['lon'] as num).toDouble());
          return ListTile(
            dense: true,
            leading: const Icon(Icons.history, size: 20),
            title: Text('${m['name']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            trailing: _distWidget(pos),
            onTap: () => _pickRecent(m),
          );
        }),
      ]),
    );
  }

  Widget _segment() {
    Widget seg(String k, String label) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _timing = k),
            child: Container(
              margin: const EdgeInsets.all(4),
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: _timing == k ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                boxShadow: _timing == k ? const [BoxShadow(color: Colors.black12, blurRadius: 6)] : null,
              ),
              child: Center(
                child: Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _timing == k ? brand : const Color(0xFF6B7280))),
              ),
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFEEF0F6), borderRadius: BorderRadius.circular(13)),
      child: Row(children: [seg('now', 'Now'), seg('depart', 'Depart'), seg('arrive', 'Arrive')]),
    );
  }

  Widget _dtButton(String label, IconData icon, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF1A1C22),
          minimumSize: const Size.fromHeight(50),
          side: const BorderSide(color: Color(0xFFE7E8EE))),
    );
  }
}
