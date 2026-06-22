import 'package:flutter/material.dart';
import '../../services/admin_auth_service.dart';
import 'admin_login_screen.dart';
import 'admin_inventory_screen.dart';
import 'admin_audit_logs_screen.dart';
import 'admin_orders_screen.dart';
import 'secure_products_screen.dart';
import 'staff_screen.dart';

class SecureAdminDashboard extends StatefulWidget {
  const SecureAdminDashboard({super.key});

  @override
  State<SecureAdminDashboard> createState() => _State();
}

class _State extends State<SecureAdminDashboard> {
  final AdminAuthService _auth = AdminAuthService();
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (!_auth.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) =>
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminLoginScreen())));
      return;
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final stats = await _auth.getDashboard();
      setState(() { _stats = stats; _loading = false; });
    } catch (e) {
      if (e.toString().contains('401') || e.toString().contains('Admin')) {
        _auth.logout();
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminLoginScreen()));
      }
      setState(() => _loading = false);
    }
  }

  void _logout() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Logout'), content: const Text('Are you sure you want to logout?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () { _auth.logout(); Navigator.pop(ctx);
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminLoginScreen()));
        }, child: const Text('Logout', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Admin Dashboard', style: TextStyle(fontSize: 18)),
          Text(_auth.email, style: TextStyle(fontSize: 11, color: Colors.indigo[200])),
        ]),
        backgroundColor: Colors.indigo[800],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final s = _stats ?? {};
    return ListView(padding: const EdgeInsets.all(16), children: [
      // Stats grid
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.5,
        children: [
          _stat('Products', '${s['total_products'] ?? 0}', Icons.inventory_2, Colors.blue),
          _stat('Customers', '${s['total_customers'] ?? 0}', Icons.people, Colors.purple),
          _stat('Orders', '${s['total_orders'] ?? 0}', Icons.receipt_long, Colors.orange),
          _stat('Today', '${s['orders_today'] ?? 0} orders', Icons.today, Colors.teal),
        ],
      ),
      const SizedBox(height: 12),

      // Revenue
      Row(children: [
        Expanded(child: _revenueCard('Today', s['revenue_today'] ?? 0, Colors.blue)),
        const SizedBox(width: 12),
        Expanded(child: _revenueCard('This Month', s['revenue_this_month'] ?? 0, Colors.blue)),
      ]),
      const SizedBox(height: 12),

      // Alerts
      if ((s['low_stock'] ?? 0) > 0 || (s['out_of_stock'] ?? 0) > 0)
        Row(children: [
          if ((s['low_stock'] ?? 0) > 0)
            Expanded(child: _alert('Low Stock', '${s['low_stock']}', Colors.orange)),
          if ((s['low_stock'] ?? 0) > 0 && (s['out_of_stock'] ?? 0) > 0)
            const SizedBox(width: 12),
          if ((s['out_of_stock'] ?? 0) > 0)
            Expanded(child: _alert('Out of Stock', '${s['out_of_stock']}', Colors.red)),
        ]),
      const SizedBox(height: 20),

      // Order status breakdown
      if (s['orders_by_status'] != null) ...[
        const Text('Orders by Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(children: (s['orders_by_status'] as Map<String, dynamic>).entries.map((e) {
            final total = s['total_orders'] as int? ?? 1;
            final pct = total > 0 ? (e.value as int) / total : 0.0;
            return Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(e.key ?? 'Unknown', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _statusColor(e.key ?? ''))),
                Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: pct, minHeight: 6, backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation(_statusColor(e.key ?? '')))),
            ]));
          }).toList()),
        ),
      ],
      const SizedBox(height: 20),

      // Quick actions
      const Text('Manage', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      _action(Icons.receipt_long, 'Orders', 'View orders, mark packed for delivery', Colors.orange,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminOrdersScreen()))),
      _action(Icons.shopping_bag, 'Products', 'Add, edit, delete, set prices', Colors.blue,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SecureProductsScreen()))),
      _action(Icons.inventory, 'Inventory', 'Stock levels and alerts', Colors.teal,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminInventoryScreen()))),
      _action(Icons.delivery_dining, 'Delivery Staff', 'Add or remove delivery employees', Colors.indigo,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffScreen()))),
      _action(Icons.history, 'Audit Logs', 'Track all admin actions', Colors.grey,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAuditLogsScreen()))),
    ]);
  }

  Widget _stat(String label, String value, IconData icon, Color color) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 20)),
      Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
    ]),
  );

  Widget _revenueCard(String label, num value, Color color) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, color: color)),
      const SizedBox(height: 4),
      Text('₹${value.toStringAsFixed(0)}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
    ]),
  );

  Widget _alert(String label, String value, Color color) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.3))),
    child: Row(children: [
      Icon(Icons.warning_amber, color: color, size: 22),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ]),
    ]),
  );

  Widget _action(IconData icon, String title, String sub, Color color, VoidCallback onTap) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
    child: ListTile(
      leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      trailing: const Icon(Icons.chevron_right),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onTap: onTap,
    ),
  );

  Color _statusColor(String s) => switch (s.toLowerCase()) {
    'confirmed' => Colors.blue, 'packed' => Colors.orange, 'out for delivery' => Colors.purple,
    'delivered' => Colors.blue, 'cancelled' => Colors.red, 'pending' => Colors.grey, _ => Colors.grey,
  };
}
