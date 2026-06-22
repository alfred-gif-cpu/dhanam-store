import 'package:flutter/material.dart';
import '../../services/admin_service.dart';

class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  final AdminService _admin = AdminService();
  List<dynamic> _orders = [];
  bool _loading = true;
  String? _statusFilter;
  int _page = 1;
  int _total = 0;

  static const _statuses = ['confirmed', 'packed', 'shipped', 'delivered', 'cancelled'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _admin.getOrders(page: _page, status: _statusFilter);
      setState(() { _orders = data['orders']; _total = data['total']; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Color _statusColor(String status) => switch (status) {
    'confirmed' => Colors.blue,
    'packed' => Colors.orange,
    'shipped' => Colors.purple,
    'delivered' => Colors.blue,
    'cancelled' => Colors.red,
    _ => Colors.grey,
  };

  void _showStatusDialog(Map<String, dynamic> order) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Update Order #${(order['order_number'] ?? order['id']).toString().substring(0, 10)}'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        children: _statuses.map((s) => SimpleDialogOption(
          onPressed: () async {
            Navigator.pop(ctx);
            await _admin.updateOrderStatus(order['id'], s);
            _load();
          },
          child: Row(children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: _statusColor(s), shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Text(s.toUpperCase(), style: TextStyle(fontWeight: order['status'] == s ? FontWeight.bold : FontWeight.normal)),
            if (order['status'] == s) ...[const Spacer(), const Icon(Icons.check, size: 18, color: Colors.blue)],
          ]),
        )).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(title: Text('Orders ($_total)'), backgroundColor: Colors.indigo, foregroundColor: Colors.white, elevation: 0),
      body: Column(children: [
        // Status filter chips
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              _filterChip('All', null),
              ..._statuses.map((s) => _filterChip(s[0].toUpperCase() + s.substring(1), s)),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _orders.isEmpty
                  ? Center(child: Text('No orders found', style: TextStyle(color: Colors.grey[600])))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _orders.length,
                        itemBuilder: (context, index) {
                          final o = _orders[index] as Map<String, dynamic>;
                          final items = o['items'] as List? ?? [];
                          final status = o['status'] ?? '';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text('#${(o['order_number'] ?? o['id']).toString().substring(0, 10).toUpperCase()}',
                                    style: const TextStyle(fontWeight: FontWeight.bold))),
                                GestureDetector(
                                  onTap: () => _showStatusDialog(o),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                    child: Text(status.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _statusColor(status))),
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 6),
                              Text('${items.length} items • ₹${(o['grand_total'] ?? 0).toStringAsFixed(0)}',
                                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                              Text('${o['payment_method'] ?? 'N/A'} • ${(o['created_at'] ?? '').toString().split('T').first}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                            ]),
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _filterChip(String label, String? status) {
    final selected = _statusFilter == status;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : Colors.grey[700])),
        selected: selected,
        onSelected: (_) { _statusFilter = selected ? null : status; _page = 1; _load(); },
        selectedColor: Colors.indigo,
        checkmarkColor: Colors.white,
        backgroundColor: Colors.white,
        side: BorderSide(color: selected ? Colors.indigo : Colors.grey[300]!),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
