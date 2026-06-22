import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'orders_screen.dart';
import 'address/address_list_screen.dart';
import 'edit_profile_screen.dart';
import 'login_screen.dart';
import '../services/admin_auth_service.dart';
import 'admin/admin_login_screen.dart';
import 'admin/secure_admin_dashboard.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _auth = AuthService();

  @override
  void initState() {
    super.initState();
    _auth.addListener(_refresh);
  }

  @override
  void dispose() {
    _auth.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    if (!_auth.isLoggedIn) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(title: const Text('My Account'), centerTitle: true, elevation: 0),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(color: Colors.green[50], shape: BoxShape.circle),
                child: Icon(Icons.person_outline, size: 48, color: Colors.green[300]),
              ),
              const SizedBox(height: 24),
              const Text('Login to Dhanam Store', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('View orders, save addresses, and checkout faster',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Colors.grey[500])),
              const SizedBox(height: 28),
              SizedBox(
                height: 50,
                width: 200,
                child: ElevatedButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
                  child: const Text('Login / Sign Up', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
        ),
      );
    }

    final displayName = _auth.name.isNotEmpty ? _auth.name : 'Dhanam User';
    final initials = displayName.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: const Text('My Account'), centerTitle: true, elevation: 0),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // User header
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen())),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.green[100],
                  child: Text(initials, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green[700])),
                ),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(_auth.phone, style: TextStyle(color: Colors.grey[600])),
                  if (_auth.email.isNotEmpty)
                    Text(_auth.email, style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                ])),
                Icon(Icons.chevron_right, color: Colors.grey[400]),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          _tile(context, Icons.receipt_long, 'My Orders', 'Track, return, or buy again',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersScreen()))),
          _tile(context, Icons.location_on_outlined, 'My Addresses', 'Manage delivery addresses',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressListScreen()))),
          _tile(context, Icons.payment, 'Payment Methods', 'Manage saved payments', null),
          _tile(context, Icons.headset_mic_outlined, 'Help & Support', 'Get help with your orders', null),
          _tile(context, Icons.info_outline, 'About', 'App version 2.0.0', null),
          const SizedBox(height: 10),
          // Admin
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(color: Colors.indigo[50], borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              leading: Icon(Icons.admin_panel_settings, color: Colors.indigo[700]),
              title: const Text('Admin Dashboard', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.indigo)),
              subtitle: Text('Manage products, orders, users', style: TextStyle(fontSize: 12, color: Colors.indigo[300])),
              trailing: const Icon(Icons.chevron_right, color: Colors.indigo),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onTap: () {
                if (AdminAuthService().isLoggedIn) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SecureAdminDashboard()));
                } else {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminLoginScreen()));
                }
              },
            ),
          ),
          // Logout
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              leading: Icon(Icons.logout, color: Colors.red[400]),
              title: const Text('Logout', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onTap: () => _showLogoutDialog(),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () { _auth.logout(); Navigator.pop(ctx); },
            child: const Text('Logout', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, String subtitle, VoidCallback? onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Icon(icon, color: Colors.green[700]),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        trailing: const Icon(Icons.chevron_right),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: onTap ?? () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$title — coming soon'), behavior: SnackBarBehavior.floating)),
      ),
    );
  }
}
