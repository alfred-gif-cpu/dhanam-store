import 'package:flutter/material.dart';
import '../../services/customer_service.dart';
import 'edit_customer_profile_screen.dart';
import 'customer_addresses_screen.dart';
import 'customer_wallet_screen.dart';
import 'customer_loyalty_screen.dart';
import 'customer_orders_screen.dart';
import 'customer_settings_screen.dart';

class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({super.key});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  final CustomerService _cs = CustomerService();

  @override
  void initState() {
    super.initState();
    _cs.addListener(_r);
  }

  @override
  void dispose() {
    _cs.removeListener(_r);
    super.dispose();
  }

  void _r() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: const Text('My Account'), centerTitle: true, elevation: 0),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Profile card
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditCustomerProfileScreen())),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: Colors.green[100],
                backgroundImage: _cs.profileImage.isNotEmpty ? NetworkImage(_cs.profileImage) : null,
                child: _cs.profileImage.isEmpty ? Icon(Icons.person, size: 36, color: Colors.green[700]) : null,
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_cs.name.isNotEmpty ? _cs.name : 'Set up your profile', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(_cs.phone, style: TextStyle(color: Colors.grey[600])),
                if (_cs.email.isNotEmpty) Text(_cs.email, style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                const SizedBox(height: 6),
                Text('ID: ${_cs.customerId}', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
              ])),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ]),
          ),
        ),
        const SizedBox(height: 12),

        // Wallet & Points row
        Row(children: [
          Expanded(child: _infoCard(Icons.account_balance_wallet, 'Wallet', '₹${_cs.walletBalance.toStringAsFixed(0)}', Colors.blue,
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerWalletScreen())))),
          const SizedBox(width: 12),
          Expanded(child: _infoCard(Icons.stars, 'Points', '${_cs.loyaltyPoints}', Colors.orange,
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerLoyaltyScreen())))),
        ]),
        const SizedBox(height: 16),

        _tile(Icons.receipt_long, 'My Orders', 'Track and reorder',
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerOrdersScreen()))),
        _tile(Icons.location_on_outlined, 'My Addresses', 'Manage delivery addresses',
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerAddressesScreen()))),
        _tile(Icons.settings_outlined, 'Account Settings', 'Preferences and notifications',
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerSettingsScreen()))),
      ]),
    );
  }

  Widget _infoCard(IconData icon, String label, String value, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 10),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 13, color: color.withValues(alpha: 0.7))),
        ]),
      ),
    );
  }

  Widget _tile(IconData icon, String title, String sub, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Icon(icon, color: Colors.green[700]),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        trailing: const Icon(Icons.chevron_right),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: onTap,
      ),
    );
  }
}
