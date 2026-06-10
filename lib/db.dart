import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Local database (Hive). Works on Android, iOS and Web.
/// Stores users, the current session, and per-user trip history.
/// Designed so it can later sync to a cloud backend.
class Db {
  static late Box _users;
  static late Box _session;
  static late Box _trips;

  static Future<void> init() async {
    await Hive.initFlutter();
    _users = await Hive.openBox('users');
    _session = await Hive.openBox('session');
    _trips = await Hive.openBox('trips');
  }

  static String _hash(String p) => sha256.convert(utf8.encode(p)).toString();

  static String? get currentEmail => _session.get('currentUser') as String?;
  static bool get isLoggedIn => currentEmail != null;
  static Map? get currentUser {
    final e = currentEmail;
    return e == null ? null : (_users.get(e) as Map?);
  }

  static String get currentName => (currentUser?['name'] as String?) ?? 'Traveller';

  /// Returns null on success, or a human-readable error message.
  static String? register(String name, String email, String pass) {
    name = name.trim();
    email = email.trim().toLowerCase();
    if (name.isEmpty) return 'Please enter your name';
    if (!email.contains('@') || !email.contains('.')) return 'Enter a valid email';
    if (pass.length < 4) return 'Password must be at least 4 characters';
    if (_users.containsKey(email)) return 'An account with this email already exists';
    _users.put(email, {
      'name': name,
      'email': email,
      'pass': _hash(pass),
      'createdAt': DateTime.now().toIso8601String(),
    });
    _session.put('currentUser', email);
    return null;
  }

  static String? login(String email, String pass) {
    email = email.trim().toLowerCase();
    final u = _users.get(email) as Map?;
    if (u == null) return 'No account found for this email';
    if (u['pass'] != _hash(pass)) return 'Incorrect password';
    _session.put('currentUser', email);
    return null;
  }

  static void logout() => _session.delete('currentUser');

  static Future<void> addTrip(Map<String, dynamic> trip) async {
    final e = currentEmail;
    if (e == null) return;
    final key = 'trips_$e';
    final list = ((_trips.get(key) as List?) ?? []).toList();
    list.insert(0, trip);
    await _trips.put(key, list);
  }

  static List<Map> tripsForCurrent() {
    final e = currentEmail;
    if (e == null) return [];
    final list = (_trips.get('trips_$e') as List?) ?? [];
    return list.cast<Map>();
  }

  static Map<String, double> statsForCurrent() {
    double km = 0, kcal = 0, co2 = 0;
    final trips = tripsForCurrent();
    for (final t in trips) {
      km += (t['km'] ?? 0).toDouble();
      kcal += (t['kcal'] ?? 0).toDouble();
      co2 += (t['co2'] ?? 0).toDouble();
    }
    return {'km': km, 'kcal': kcal, 'co2': co2, 'count': trips.length.toDouble()};
  }
}
