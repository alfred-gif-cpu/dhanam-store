import 'package:flutter/material.dart';
import '../../services/admin_service.dart';
import 'admin_products_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_users_screen.dart';
import 'admin_customers_screen.dart';
import 'admin_order_analytics_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final AdminService _admin = AdminService();
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stats = await _admin.getStats();
      setState(() { _stats = stats; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final s = _stats!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Stat cards
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _statCard('Products', '${s['total_products']}', Icons.inventory_2, Colors.blue),
            _statCard('Orders', '${s['total_orders']}', Icons.receipt_long, Colors.orange),
            _statCard('Users', '${s['total_users']}', Icons.people, Colors.purple),
            _statCard('Revenue', '₹${(s['total_revenue'] as num).toStringAsFixed(0)}', Icons.currency_rupee, Colors.blue),
          ],
        ),
        const SizedBox(height: 16),

        // Alert cards
        Row(children: [
          Expanded(child: _alertCard('Low Stock', '${s['low_stock']}', Colors.orange)),
          const SizedBox(width: 12),
          Expanded(child: _alertCard('Out of Stock', '${s['out_of_stock']}', Colors.red)),
        ]),
        const SizedBox(height: 20),

        // Orders by status
        _sectionTitle('Orders by status'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: (s['orders_by_status'] as Map<String, dynamic>? ?? {}).entries.map((e) {
              final total = s['total_orders'] as int;
              final pct = total > 0 ? (e.value as int) / total : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(e.key.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _statusColor(e.key))),
                    Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: pct, backgroundColor: Colors.grey[200], valueColor: AlwaysStoppedAnimation(_statusColor(e.key)), minHeight: 6),
                  ),
                ]),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 20),

        // Quick actions
        _sectionTitle('Manage'),
        const SizedBox(height: 8),
        _actionTile(Icons.inventory_2, 'Products', 'Add, edit, delete products', Colors.blue,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminProductsScreen()))),
        _actionTile(Icons.receipt_long, 'Orders', 'View and manage orders', Colors.orange,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminOrdersScreen()))),
        _actionTile(Icons.people, 'Users', 'View registered users', Colors.purple,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminUsersScreen()))),
        _actionTile(Icons.person_search, 'Customers', 'Manage, search, block customers', Colors.teal,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminCustomersScreen()))),
        _actionTile(Icons.analytics, 'Order Analytics', 'Revenue, trends, top products', Colors.pink,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminOrderAnalyticsScreen()))),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 22),
        ),
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
      ]),
    );
  }

  Widget _alertCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(Icons.warning_amber, color: color, size: 22),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ]),
      ]),
    );
  }

  Widget _sectionTitle(String title) => Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold));

  Widget _actionTile(IconData icon, String title, String subtitle, Color color, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        trailing: const Icon(Icons.chevron_right),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: onTap,
      ),
    );
  }

  Color _statusColor(String status) => switch (status) {
    'confirmed' => Colors.blue,
    'packed' => Colors.orange,
    'shipped' => Colors.purple,
    'delivered' => Colors.blue,
    'cancelled' => Colors.red,
    _ => Colors.grey,
  };
}
