import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/order_service.dart';
import 'order_detail_screen.dart';

class OrderListScreen extends StatefulWidget {
  const OrderListScreen({super.key});

  @override
  State<OrderListScreen> createState() => _State();
}

class _State extends State<OrderListScreen> with SingleTickerProviderStateMixin {
  final OrderService _svc = OrderService();
  late TabController _tab;
  final _tabs = ['All', 'Active', 'Delivered', 'Cancelled'];

  List<dynamic> _orders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
    _tab.addListener(() { if (!_tab.indexIsChanging) _load(); });
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  String get _statusFilter => switch (_tab.index) {
    1 => 'Confirmed',
    2 => 'Delivered',
    3 => 'Cancelled',
    _ => '',
  };

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final userId = AuthService().userId;
      final data = await _svc.getCustomerOrders(userId, status: _statusFilter);
      setState(() { _orders = data['orders'] ?? []; _loading = false; });
    } catch (e) { setState(() { _error = e.toString(); _loading = false; }); }
  }

  Color _statusColor(String s) => switch (s.toLowerCase()) {
    'pending' => Colors.grey,
    'confirmed' => Colors.blue,
    'packed' => Colors.orange,
    'out for delivery' => Colors.purple,
    'delivered' => Colors.blue,
    'cancelled' => Colors.red,
    _ => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('My Orders'), centerTitle: true, elevation: 0,
        bottom: TabBar(controller: _tab, isScrollable: true,
          labelColor: Colors.blue, unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blue, indicatorWeight: 3,
          tabs: _tabs.map((t) => Tab(text: t)).toList()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorWidget()
              : _orders.isEmpty
                  ? _empty()
                  : RefreshIndicator(onRefresh: _load, child: ListView.builder(
                  padding: const EdgeInsets.all(16), itemCount: _orders.length,
                  itemBuilder: (_, i) {
                    final o = _orders[i] as Map<String, dynamic>;
                    final items = o['items'] as List? ?? [];
                    final status = o['order_status'] ?? o['status'] ?? '';
                    final orderId = o['order_id'] ?? '';
                    final total = (o['total_amount'] ?? o['grand_total'] ?? 0).toDouble();

                    return GestureDetector(
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: orderId)));
                        _load();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text('#$orderId', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                              child: Text(status.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _statusColor(status)))),
                          ]),
                          const SizedBox(height: 10),
                          ...items.take(2).map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(children: [
                              Container(width: 36, height: 36, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                                child: const Icon(Icons.shopping_bag_outlined, size: 18, color: Colors.grey)),
                              const SizedBox(width: 10),
                              Expanded(child: Text('${item['quantity']}× ${item['product_name'] ?? item['name'] ?? ''}',
                                  style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              Text('₹${((item['price'] ?? 0) * (item['quantity'] ?? 0)).toStringAsFixed(0)}',
                                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                            ]),
                          )),
                          if (items.length > 2)
                            Padding(padding: const EdgeInsets.only(top: 4),
                              child: Text('+${items.length - 2} more items', style: TextStyle(fontSize: 12, color: Colors.grey[500]))),
                          const Divider(height: 24),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text((o['created_at'] ?? '').toString().split('T').first, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                            Text('₹${total.toStringAsFixed(0)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.blue)),
                          ]),
                        ]),
                      ),
                    );
                  })),
    );
  }

  Widget _empty() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.receipt_long, size: 64, color: Colors.grey[300]),
    const SizedBox(height: 16),
    Text('No orders found', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
  ]));

  Widget _errorWidget() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey[400]),
    const SizedBox(height: 16),
    Text('Could not load orders', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
    const SizedBox(height: 16),
    ElevatedButton.icon(
      onPressed: _load,
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('Retry'),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    ),
  ]));
}
