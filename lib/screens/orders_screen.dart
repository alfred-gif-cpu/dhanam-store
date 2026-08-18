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
  String? _error;
  String? _cancelling;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final orders = await _api.getOrders(AuthService().userId);
      setState(() { _orders = orders; _loading = false; });
    } catch (e) {
      // This used to swallow the error and fall through to the empty state, so
      // a customer whose orders failed to load was told they had never ordered.
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  /// The server refuses a cancel once an order is Delivered, Cancelled or
  /// refunded. This stops one step earlier: once the order is out for
  /// delivery the driver has already gone, and that is a phone call to the
  /// shop rather than a button.
  bool _canCancel(String status) =>
      const ['pending', 'confirmed', 'packed'].contains(status.toLowerCase());

  Future<void> _cancel(Order order) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel this order?'),
        content: Text('Order #${_shortId(order.id)} will be cancelled and the '
            'items put back on the shelf. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep order')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel order',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (yes != true) return;

    setState(() => _cancelling = order.id);
    try {
      await _api.cancelOrder(order.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Order cancelled'), behavior: SnackBarBehavior.floating));
      await _load();
    } catch (e) {
      if (!mounted) return;
      // Failing quietly here would leave the order looking cancelled when it
      // is not, and the shop would still deliver it.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not cancel: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _cancelling = null);
    }
  }

  static String _shortId(String id) =>
      id.length <= 6 ? id : id.substring(id.length - 6).toUpperCase();

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
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.cloud_off, size: 56, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text('Could not load your orders', style: TextStyle(fontSize: 17, color: Colors.grey[700])),
                    const SizedBox(height: 6),
                    Text(_error!, textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: _load, child: const Text('Try again')),
                  ]),
                ))
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
                            Text('Order #${_shortId(order.id)}',
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
                          if (_canCancel(order.status)) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              height: 42,
                              child: OutlinedButton(
                                onPressed: _cancelling == null ? () => _cancel(order) : null,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: _cancelling == order.id
                                    ? const SizedBox(height: 18, width: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red))
                                    : const Text('Cancel Order',
                                        style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ]),
                      );
                    },
                  ),
                ),
    );
  }
}
