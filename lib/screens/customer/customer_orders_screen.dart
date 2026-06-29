import 'package:flutter/material.dart';
import '../../services/customer_service.dart';

class CustomerOrdersScreen extends StatefulWidget {
  const CustomerOrdersScreen({super.key});

  @override
  State<CustomerOrdersScreen> createState() => _State();
}

class _State extends State<CustomerOrdersScreen> {
  final CustomerService _cs = CustomerService();
  List<dynamic> _orders = [];
  bool _loading = true;
  String? _error;
  final int _page = 1;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _cs.getOrderHistory(page: _page);
      setState(() { _orders = data['orders'] ?? []; _loading = false; });
    } catch (e) { setState(() { _error = e.toString(); _loading = false; }); }
  }

  Color _statusColor(String s) => switch (s) {
    'confirmed' => Colors.blue, 'packed' => Colors.orange, 'shipped' => Colors.purple,
    'delivered' => Colors.blue, 'cancelled' => Colors.red, _ => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: const Text('My Orders'), centerTitle: true, elevation: 0),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('Could not load orders', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh, size: 18), label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
                ]))
              : _orders.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('No orders yet', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                ]))
              : RefreshIndicator(onRefresh: _load, child: ListView.builder(
                  padding: const EdgeInsets.all(16), itemCount: _orders.length,
                  itemBuilder: (_, i) {
                    final o = _orders[i] as Map<String, dynamic>;
                    final items = o['items'] as List? ?? [];
                    final status = o['status'] ?? '';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text('#${(o['order_number'] ?? o['id'] ?? '').toString().substring(0, 10).toUpperCase()}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text(status.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _statusColor(status)))),
                        ]),
                        const SizedBox(height: 8),
                        Text('${items.length} items', style: TextStyle(color: Colors.grey[600])),
                        ...items.take(3).map((item) => Text('  ${item['quantity']}× ${item['name']}', style: TextStyle(fontSize: 13, color: Colors.grey[700]))),
                        if (items.length > 3) Text('  +${items.length - 3} more', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                        const Divider(height: 20),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text((o['created_at'] ?? '').toString().split('T').first, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                          Text('₹${(o['grand_total'] ?? 0).toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
                        ]),
                      ]),
                    );
                  })),
    );
  }
}
