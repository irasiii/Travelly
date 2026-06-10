import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';

const _ink = Color(0xFF1A1C22);
const _muted = Color(0xFF6B7280);

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});
  @override
  Widget build(BuildContext context) {
    Widget item(IconData ic, String label, Widget? screen, {Color? color}) => ListTile(
          leading: Icon(ic, color: color ?? _muted),
          title: Text(label, style: TextStyle(color: color ?? _ink, fontSize: 15)),
          onTap: () {
            Scaffold.of(context).closeDrawer();
            if (screen != null) {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signed out')));
            }
          },
        );
    return Drawer(
      child: Column(children: [
        Container(
          width: double.infinity,
          color: brand,
          padding: const EdgeInsets.fromLTRB(20, 60, 20, 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            CircleAvatar(radius: 24, backgroundColor: Colors.white, child: Text('T', style: TextStyle(color: brand, fontWeight: FontWeight.w700, fontSize: 22))),
            SizedBox(height: 10),
            Text('Travelly User', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
            Text('Plan your sustainable route', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
        item(Icons.explore, 'My Trips', const TripsScreen()),
        item(Icons.bookmark_border, 'Saved & Scheduled', const SavedScreen()),
        item(Icons.bar_chart, 'Insights', const InsightsScreen()),
        item(Icons.person_outline, 'Profile', const ProfileScreen()),
        item(Icons.help_outline, 'Help & Support', const HelpScreen()),
        const Spacer(),
        const Divider(height: 1),
        item(Icons.logout, 'Sign Out', null, color: const Color(0xFFE5343D)),
      ]),
    );
  }
}

class TripsScreen extends StatelessWidget {
  const TripsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Trips'), backgroundColor: Colors.white),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🧭', style: TextStyle(fontSize: 48)),
            SizedBox(height: 10),
            Text('No trip history yet',
                style: TextStyle(color: _muted, fontWeight: FontWeight.w600, fontSize: 15)),
            SizedBox(height: 4),
            Text('Your completed trips will appear here.',
                style: TextStyle(color: _muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Saved & Scheduled'), backgroundColor: Colors.white),
      body: app.scheduled.isEmpty
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('🔖', style: TextStyle(fontSize: 48)),
                SizedBox(height: 10),
                Text('No saved or scheduled trips yet', style: TextStyle(color: _muted)),
                Text('Plan a journey, pick a route, then tap Schedule.', style: TextStyle(color: _muted, fontSize: 12)),
              ]),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Padding(padding: EdgeInsets.only(bottom: 8),
                    child: Text('SCHEDULED TRIPS', style: TextStyle(fontWeight: FontWeight.w800, color: _muted, letterSpacing: .5, fontSize: 13))),
                ...app.scheduled.asMap().entries.map((e) {
                  final it = e.value;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 11),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: Row(children: [
                      Container(width: 42, height: 42, alignment: Alignment.center,
                          decoration: BoxDecoration(color: brand, borderRadius: BorderRadius.circular(12)),
                          child: Text(it.icon, style: const TextStyle(fontSize: 20))),
                      const SizedBox(width: 13),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(it.dest, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        Text('${it.mode} · ${it.dur} · ${it.km.toStringAsFixed(1)} km', style: const TextStyle(color: _muted, fontSize: 12)),
                        Text('🚀 ${fmtDateTime(it.dep)} → 🎯 ${hhmm(it.arr)}', style: const TextStyle(color: _muted, fontSize: 12)),
                      ])),
                      IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => app.removeScheduled(e.key)),
                    ]),
                  );
                }),
              ],
            ),
    );
  }
}

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final months = ['J','F','M','A','M','J','J','A','S','O','N','D'];
    return Scaffold(
      appBar: AppBar(title: const Text('Your Impact'), backgroundColor: Colors.white),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(colors: [brand, Color(0xFF3B82F6)])),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text("Today's Activity Mix", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
            SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('312', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                Text('kcal burned', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('1.84', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                Text('kg CO₂ saved', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Monthly Trend', style: TextStyle(color: brand, fontWeight: FontWeight.w700)),
              Text('12% more sustainable trips than last month', style: TextStyle(color: _muted, fontSize: 12)),
            ])),
            Text('📈', style: TextStyle(fontSize: 22)),
          ]),
        ),
        const SizedBox(height: 18),
        const Text('MONTHLY DISTANCE BREAKDOWN', style: TextStyle(fontWeight: FontWeight.w800, color: _muted, fontSize: 13, letterSpacing: .5)),
        const SizedBox(height: 14),
        SizedBox(
          height: 130,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: months.asMap().entries.map((e) {
            final i = e.key;
            final walk = (10 + (i * 7) % 30).toDouble();
            final bus = (8 + (i * 11) % 25).toDouble();
            final car = (4 + (i * 3) % 14).toDouble();
            return Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Container(height: car, color: const Color(0xFFEF4444)),
                Container(height: bus, color: const Color(0xFFF59E0B)),
                Container(height: walk, color: const Color(0xFF16A34A)),
                const SizedBox(height: 4),
                Text(e.value, style: const TextStyle(fontSize: 9, color: _muted)),
              ])));
          }).toList()),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 16, children: const [
          _Legend(Color(0xFF16A34A), 'Active Travel'),
          _Legend(Color(0xFFF59E0B), 'Public Transit'),
          _Legend(Color(0xFFEF4444), 'Private Motor'),
        ]),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color c; final String label;
  const _Legend(this.c, this.label);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, color: c), const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: _muted)),
      ]);
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    Widget row(IconData ic, String k, String v, {Color? vc}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(children: [
            SizedBox(width: 26, child: Icon(ic, size: 18, color: _muted)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(k, style: const TextStyle(fontSize: 12, color: _muted)),
              Text(v, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: vc)),
            ])),
          ]),
        );
    Widget title(String t) => Padding(padding: const EdgeInsets.fromLTRB(2, 18, 2, 4),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, color: _muted, fontSize: 13, letterSpacing: .5)));
    return Scaffold(
      appBar: AppBar(title: const Text('Profile'), backgroundColor: Colors.white),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: const [
          CircleAvatar(radius: 31, backgroundColor: brand, child: Text('T', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700))),
          SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Travelly User', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            Text('Plan your sustainable route', style: TextStyle(color: _muted, fontSize: 12)),
          ]),
        ]),
        title('ACCOUNT INFORMATION'),
        row(Icons.email_outlined, 'Email', 'ibrahim.rasras@connect.qut.edu.au'),
        row(Icons.badge_outlined, 'User ID', '19be94e8-e0a1-70bb-3159'),
        row(Icons.person_outline, 'Name', 'Not set'),
        row(Icons.phone_outlined, 'Phone', 'Not set'),
        title('PREFERENCES'),
        row(Icons.directions_walk, 'Preferred Transport Mode', 'Walking'),
        row(Icons.notifications_active_outlined, 'Notifications', 'Enabled', vc: const Color(0xFF16A34A)),
        row(Icons.straighten, 'Units', 'Metric (km)'),
        title('PRIVACY & CONSENT'),
        row(Icons.shield_outlined, 'Location tracking', 'Always allow', vc: const Color(0xFF16A34A)),
      ]),
    );
  }
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final faqs = [
      ['How is CO₂ reduction calculated?', 'We compare your chosen transport method against the average emissions of a standard petrol car for the same distance.'],
      ['What is the \'Dynamic Hub\'?', 'It\'s your central command. It tracks your live movement by default, but turns into a journey planner when you enter a destination.'],
      ['Why isn\'t my trip tracking?', 'Ensure \'Always Allow\' location permissions are enabled in your phone settings so we can track you even when the screen is off.'],
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Help Centre'), backgroundColor: Colors.white),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ...faqs.map((f) => Card(
              color: Colors.white, elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: ExpansionTile(
                title: Text(f[0], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                childrenPadding: const EdgeInsets.fromLTRB(15, 0, 15, 15),
                children: [Align(alignment: Alignment.centerLeft, child: Text(f[1], style: const TextStyle(color: _muted, fontSize: 13)))],
              ),
            )),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: const Center(child: Text('✉️ Still need help? Contact Us', style: TextStyle(color: brand, fontWeight: FontWeight.w700))),
        ),
      ]),
    );
  }
}
