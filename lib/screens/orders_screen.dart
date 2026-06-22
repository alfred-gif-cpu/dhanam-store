import 'package:flutter/material.dart';
import '../models/order.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final ApiService _api = ApiService();
  List<Order> _orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final orders = await _api.getOrders(AuthService().userId);
      setState(() { _orders = orders; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Color _statusColor(String status) {
    return switch (status) {
      'confirmed' => Colors.blue,
      'packed' => Colors.orange,
      'shipped' => Colors.purple,
      'delivered' => Colors.blue,
      'cancelled' => Colors.red,
      _ => Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: const Text('My Orders'), centerTitle: true, elevation: 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('No orders yet', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _orders.length,
                    itemBuilder: (context, index) {
                      final order = _orders[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text('Order #${order.id.substring(order.id.length - 6).toUpperCase()}',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: _statusColor(order.status).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                              child: Text(order.status.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _statusColor(order.status))),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          Text('${order.items.length} items', style: TextStyle(color: Colors.grey[600])),
                          const SizedBox(height: 4),
                          ...order.items.take(3).map((item) => Text('  ${item.quantity}× ${item.name}', style: TextStyle(fontSize: 13, color: Colors.grey[700]))),
                          if (order.items.length > 3) Text('  +${order.items.length - 3} more', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                          const Divider(height: 20),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text(order.createdAt.split('T').first, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                            Text('₹${order.grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
                          ]),
                        ]),
                      );
                    },
                  ),
                ),
    );
  }
}
