import 'package:flutter/material.dart';
import '../../services/admin_auth_service.dart';
import 'secure_admin_dashboard.dart';

class AdminChangePasswordScreen extends StatefulWidget {
  const AdminChangePasswordScreen({super.key});

  @override
  State<AdminChangePasswordScreen> createState() => _State();
}

class _State extends State<AdminChangePasswordScreen> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() { _current.dispose(); _new.dispose(); _confirm.dispose(); super.dispose(); }

  Future<void> _change() async {
    if (_new.text.length < 8) { setState(() => _error = 'Password must be at least 8 characters'); return; }
    if (_new.text != _confirm.text) { setState(() => _error = 'Passwords do not match'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      await AdminAuthService().changePassword(_current.text, _new.text);
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SecureAdminDashboard()));
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo[900],
      body: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_reset, size: 48, color: Colors.white),
          const SizedBox(height: 16),
          const Text('Change Password', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 8),
          Text('You must change your password before continuing', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14), textAlign: TextAlign.center),
          const SizedBox(height: 32),
          _field(_current, 'Current Password'),
          const SizedBox(height: 14),
          _field(_new, 'New Password'),
          const SizedBox(height: 14),
          _field(_confirm, 'Confirm Password'),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 16),
            child: Text(_error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 28),
          SizedBox(width: double.infinity, height: 54, child: ElevatedButton(
            onPressed: _loading ? null : _change,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.indigo[900],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
            child: _loading ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.indigo[900]))
                : const Text('Update Password', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          )),
        ]),
      )),
    );
  }

  Widget _field(TextEditingController c, String label) => TextField(
    controller: c, obscureText: true, style: const TextStyle(color: Colors.white, fontFamily: 'AppSans'),
    decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: Colors.white54),
      prefixIcon: const Icon(Icons.lock_outline, color: Colors.white54),
      filled: true, fillColor: Colors.white.withValues(alpha: 0.1),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white, width: 2))),
  );
}
