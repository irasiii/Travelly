import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../db.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  String? _error;

  void _login() {
    final err = Db.login(_email.text, _pass.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    context.read<AppState>().refreshAuth();
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Brand(),
                const SizedBox(height: 28),
                const Text('Welcome back',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('Sign in to plan and track your trips.',
                    style: TextStyle(color: Color(0xFF6B7280))),
                const SizedBox(height: 20),
                _input(_email, 'Email', Icons.email_outlined,
                    keyboard: TextInputType.emailAddress),
                const SizedBox(height: 12),
                _input(_pass, 'Password', Icons.lock_outline, obscure: true),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: Color(0xFFE5343D), fontSize: 13)),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _login,
                  style: FilledButton.styleFrom(
                      backgroundColor: brand, minimumSize: const Size.fromHeight(52)),
                  child: const Text('Sign In',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 14),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text("Don't have an account? ",
                      style: TextStyle(color: Color(0xFF6B7280))),
                  GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const RegisterScreen())),
                    child: const Text('Register',
                        style: TextStyle(color: brand, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  String? _error;

  void _register() {
    final err = Db.register(_name.text, _email.text, _pass.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    context.read<AppState>().refreshAuth();
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Brand(),
                const SizedBox(height: 24),
                const Text('Create your account',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('Register to start earning sustainable rewards.',
                    style: TextStyle(color: Color(0xFF6B7280))),
                const SizedBox(height: 20),
                _input(_name, 'Full name', Icons.person_outline),
                const SizedBox(height: 12),
                _input(_email, 'Email', Icons.email_outlined,
                    keyboard: TextInputType.emailAddress),
                const SizedBox(height: 12),
                _input(_pass, 'Password', Icons.lock_outline, obscure: true),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: Color(0xFFE5343D), fontSize: 13)),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _register,
                  style: FilledButton.styleFrom(
                      backgroundColor: brand, minimumSize: const Size.fromHeight(52)),
                  child: const Text('Create Account',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _input(TextEditingController c, String hint, IconData icon,
    {bool obscure = false, TextInputType? keyboard}) {
  return TextField(
    controller: c,
    obscureText: obscure,
    keyboardType: keyboard,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: const Color(0xFFF1F2F7),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    ),
  );
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
              color: brand, borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.location_on, color: Colors.white, size: 40),
        ),
        const SizedBox(height: 12),
        const Text('Travelly',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: brand)),
        const Text('Sustainable journeys', style: TextStyle(color: Color(0xFF6B7280))),
      ]);
}
