import 'package:flutter/material.dart';
import '../../services/admin_auth_service.dart';
import '../../services/notification_service.dart';
import 'secure_admin_dashboard.dart';
import 'admin_change_password_screen.dart';
import 'delivery_dashboard_screen.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _State();
}

class _State extends State<AdminLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() { _email.dispose(); _password.dispose(); super.dispose(); }

  Future<void> _login() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final auth = AdminAuthService();
      final mustChange = await auth.login(_email.text.trim(), _password.text);

      // Subscribe to the role-specific notification topic
      final ns = NotificationService();
      if (auth.isOwner) {
        ns.subscribeToTopic('owner');
        ns.unsubscribeFromTopic('delivery');
      } else {
        ns.subscribeToTopic('delivery');
        ns.unsubscribeFromTopic('owner');
      }

      if (mounted) {
        if (mustChange) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminChangePasswordScreen()));
        } else if (auth.isDelivery) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DeliveryDashboardScreen()));
        } else {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SecureAdminDashboard()));
        }
      }
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo[900],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: const Icon(Icons.admin_panel_settings, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 24),
            const Text('Admin Panel', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 4),
            Text('Dhanam Stores', style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.7))),
            const SizedBox(height: 40),

            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDec('Email', Icons.email_outlined),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: _obscure,
              style: const TextStyle(color: Colors.white),
              onSubmitted: (_) => _login(),
              decoration: _inputDec('Password', Icons.lock_outline).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                  ]),
                ),
              ),

            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity, height: 54,
              child: ElevatedButton(
                onPressed: _loading ? null : _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white, foregroundColor: Colors.indigo[900],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                child: _loading
                    ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.indigo[900]))
                    : const Text('Sign In', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  InputDecoration _inputDec(String label, IconData icon) => InputDecoration(
    labelText: label, labelStyle: const TextStyle(color: Colors.white54),
    prefixIcon: Icon(icon, color: Colors.white54),
    filled: true, fillColor: Colors.white.withValues(alpha: 0.1),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white, width: 2)),
  );
}
