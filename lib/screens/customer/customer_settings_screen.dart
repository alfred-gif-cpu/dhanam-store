import 'package:flutter/material.dart';
import '../../services/customer_service.dart';

class CustomerSettingsScreen extends StatefulWidget {
  const CustomerSettingsScreen({super.key});

  @override
  State<CustomerSettingsScreen> createState() => _State();
}

class _State extends State<CustomerSettingsScreen> {
  bool _notifications = true;
  bool _promotions = true;
  bool _orderUpdates = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: const Text('Settings'), centerTitle: true, elevation: 0),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Notifications', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _switchTile(Icons.notifications_outlined, 'Push Notifications', 'Receive order and delivery updates', _notifications,
            (v) => setState(() => _notifications = v)),
        _switchTile(Icons.local_offer_outlined, 'Promotional Offers', 'Get deals and discount alerts', _promotions,
            (v) => setState(() => _promotions = v)),
        _switchTile(Icons.local_shipping_outlined, 'Order Updates', 'Track your order in real-time', _orderUpdates,
            (v) => setState(() => _orderUpdates = v)),

        const SizedBox(height: 20),
        const Text('Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _tile(Icons.lock_outline, 'Change Password', () {}),
        _tile(Icons.privacy_tip_outlined, 'Privacy Policy', () {}),
        _tile(Icons.description_outlined, 'Terms of Service', () {}),
        _tile(Icons.info_outline, 'About App', () => _showAbout()),

        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: ListTile(
            leading: Icon(Icons.delete_outline, color: Colors.red[400]),
            title: const Text('Delete Account', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            subtitle: Text('Permanently delete your account and data', style: TextStyle(fontSize: 12, color: Colors.red[300])),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onTap: () => showDialog(context: context, builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Delete Account'),
              content: const Text('This will permanently delete your account, orders, and all data. This cannot be undone.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                TextButton(onPressed: () { Navigator.pop(ctx); }, child: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
              ],
            )),
          ),
        ),
      ]),
    );
  }

  Widget _switchTile(IconData icon, String title, String sub, bool value, ValueChanged<bool> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: SwitchListTile(
        secondary: Icon(icon, color: Colors.green[700]),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        value: value, onChanged: onChanged, activeColor: Colors.green,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _tile(IconData icon, String title, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Icon(icon, color: Colors.green[700]),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: onTap,
      ),
    );
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'Dhanam Store',
      applicationVersion: '2.0.0',
      applicationIcon: Icon(Icons.storefront, size: 48, color: Colors.green[700]),
      children: [const Text('Your neighbourhood grocery store, delivering fresh products in 10 minutes.')],
    );
  }
}
