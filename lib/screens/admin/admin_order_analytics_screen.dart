import 'package:flutter/material.dart';
import '../../services/order_service.dart';

class AdminOrderAnalyticsScreen extends StatefulWidget {
  const AdminOrderAnalyticsScreen({super.key});

  @override
  State<AdminOrderAnalyticsScreen> createState() => _State();
}

class _State extends State<AdminOrderAnalyticsScreen> {
  final OrderService _svc = OrderService();
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final data = await _svc.getAnalytics();
      setState(() { _data = data; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(title: const Text('Order Analytics'), backgroundColor: Colors.indigo, foregroundColor: Colors.white, elevation: 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
              // Revenue cards
              Row(children: [
                Expanded(child: _card('Revenue Today', '₹${(_data?['revenue_today'] ?? 0).toStringAsFixed(0)}', Icons.today, Colors.blue)),
                const SizedBox(width: 12),
                Expanded(child: _card('This Month', '₹${(_data?['revenue_this_month'] ?? 0).toStringAsFixed(0)}', Icons.calendar_month, Colors.blue)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _card('Orders Today', '${_data?['orders_today'] ?? 0}', Icons.receipt, Colors.orange)),
                const SizedBox(width: 12),
                Expanded(child: _card('Total Orders', '${_data?['total_orders'] ?? 0}', Icons.receipt_long, Colors.purple)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _card('Avg Order', '₹${(_data?['avg_order_value'] ?? 0).toStringAsFixed(0)}', Icons.trending_up, Colors.teal)),
                const SizedBox(width: 12),
                Expanded(child: _card('Delivery Rate', '${_data?['delivery_success_rate'] ?? 0}%', Icons.local_shipping, Colors.blue)),
              ]),
              const SizedBox(height: 12),
              // Cancel rate
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red[50], borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red[200]!)),
                child: Row(children: [
                  Icon(Icons.cancel, color: Colors.red[700]),
                  const SizedBox(width: 12),
                  Text('Cancellation Rate: ${_data?['cancellation_rate'] ?? 0}%',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red[700])),
                ]),
              ),
              const SizedBox(height: 20),
              // Top products
              const Text('Top Selling Products', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...(_data?['top_selling_products'] as List? ?? []).asMap().entries.map((e) {
                final p = e.value as Map<String, dynamic>;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(color: Colors.indigo[50], borderRadius: BorderRadius.circular(8)),
                      child: Center(child: Text('${e.key + 1}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo[700]))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${p['quantity']} sold', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ])),
                    Text('₹${(p['revenue'] ?? 0).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  ]),
                );
              }),
            ])),
    );
  }

  Widget _card(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20)),
        const SizedBox(height: 10),
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ]),
    );
  }
}
