import 'package:flutter/material.dart';
import '../../services/admin_auth_service.dart';

class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  final AdminAuthService _admin = AdminAuthService();
  List<dynamic> _orders = [];
  bool _loading = true;
  String? _error;
  String? _statusFilter;
  int _page = 1;
  int _total = 0;

  static const _statuses = ['Confirmed', 'Packed', 'Out For Delivery', 'Delivered', 'Cancelled'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _admin.getOrders(page: _page, status: _statusFilter ?? '');
      setState(() { _orders = data['orders']; _total = data['total']; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Color _statusColor(String status) => switch (status) {
    'Confirmed' => Colors.blue,
    'Packed' => Colors.orange,
    'Out For Delivery' => Colors.purple,
    'Delivered' => Colors.green,
    'Cancelled' => Colors.red,
    _ => Colors.grey,
  };

  void _showStatusDialog(Map<String, dynamic> order) {
    final orderId = order['order_id'] ?? order['id'];
    final current = order['order_status'] ?? '';
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Update $orderId'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        children: _statuses.map((s) => SimpleDialogOption(
          onPressed: () async {
            Navigator.pop(ctx);
            try {
              await _admin.updateOrderStatus(orderId, s);
              if (mounted && s == 'Packed') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Delivery staff notified'), backgroundColor: Colors.green));
              }
            } catch (e) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
            }
            _load();
          },
          child: Row(children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: _statusColor(s), shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Text(s, style: TextStyle(fontWeight: current == s ? FontWeight.bold : FontWeight.normal)),
            if (current == s) ...[const Spacer(), const Icon(Icons.check, size: 18, color: Colors.blue)],
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
              ..._statuses.map((s) => _filterChip(s, s)),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('Could not load orders', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh, size: 18), label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
                    ]))
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
                          final status = o['order_status'] ?? 'Confirmed';
                          // The card showed a count and no way to see what was
                          // in the order — the owner had to open the web panel
                          // to answer "what did they actually buy". The status
                          // pill keeps its own tap, so changing status is still
                          // one press rather than two.
                          return InkWell(
                            onTap: () => _showOrderDetails(o),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text('${o['order_id'] ?? o['id']}',
                                    style: const TextStyle(fontWeight: FontWeight.bold))),
                                GestureDetector(
                                  onTap: () => _showStatusDialog(o),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                    child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _statusColor(status))),
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 6),
                              Text('${items.length} items • ₹${(o['grand_total'] ?? 0).toStringAsFixed(0)}',
                                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                              Text('${o['payment_method'] ?? 'N/A'} • ${(o['created_at'] ?? '').toString().split('T').first}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                            ]),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }

  /// What was actually ordered.
  ///
  /// Everything here already arrived with the order list, so opening it costs
  /// no request — the data was on the device all along and simply had nowhere
  /// to be seen.
  void _showOrderDetails(Map<String, dynamic> o) {
    final items = (o['items'] as List? ?? []).cast<Map<String, dynamic>>();
    final addr = (o['delivery_address'] ?? o['address']) as Map<String, dynamic>? ?? {};
    final line = [addr['line1'], addr['area'], addr['city'], addr['pincode']]
        .where((v) => v != null && v.toString().trim().isNotEmpty)
        .join(', ');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: Text(
                    (o['order_id'] ?? o['id'] ?? '').toString(),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  (o['order_status'] ?? '').toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _statusColor((o['order_status'] ?? 'Confirmed').toString()),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                '${o['payment_method'] ?? ''} - '
                    '${(o['created_at'] ?? '').toString().replaceFirst('T', ' ').split('.').first}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              if (line.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.location_on_outlined, size: 18, color: Colors.grey[500]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(line, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                  ),
                ]),
              ],
              const Divider(height: 28),
              Text(
                items.length == 1 ? '1 item' : '${items.length} items',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...items.map((i) {
                final qty = (i['quantity'] ?? 0) as num;
                final price = ((i['price'] ?? 0) as num).toDouble();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 36,
                      child: Text('${qty}x',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      child: Text((i['name'] ?? '').toString(),
                          style: const TextStyle(fontSize: 14)),
                    ),
                    const SizedBox(width: 8),
                    Text('₹${(price * qty).toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                );
              }),
              const Divider(height: 28),
              _totalRow('Subtotal', o['subtotal']),
              _totalRow('Delivery', o['delivery_fee']),
              _totalRow('Total', o['grand_total'] ?? o['total_amount'], bold: true),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showStatusDialog(o);
                  },
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Change status'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _totalRow(String label, dynamic value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: TextStyle(
                fontSize: bold ? 15 : 13,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                color: bold ? Colors.black : Colors.grey[700],
              )),
          Text('₹${((value ?? 0) as num).toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: bold ? 15 : 13,
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              )),
        ]),
      );

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
