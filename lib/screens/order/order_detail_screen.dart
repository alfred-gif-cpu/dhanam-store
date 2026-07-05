import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config.dart';
import '../../services/order_service.dart';
import '../../services/cart_service.dart';
import '../../models/product.dart';
import 'order_tracking_screen.dart';

class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _State();
}

class _State extends State<OrderDetailScreen> {
  final OrderService _svc = OrderService();
  Map<String, dynamic>? _order;
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _svc.getOrder(widget.orderId);
      setState(() { _order = data; _loading = false; });
    } catch (e) { setState(() { _error = e.toString(); _loading = false; }); }
  }

  Color _statusColor(String s) => switch (s.toLowerCase()) {
    'pending' => Colors.grey, 'confirmed' => Colors.blue, 'packed' => Colors.orange,
    'out for delivery' => Colors.purple, 'delivered' => Colors.blue,
    'cancelled' => Colors.red, _ => Colors.grey,
  };

  bool get _canCancel {
    final s = (_order?['order_status'] ?? '').toLowerCase();
    return s == 'pending' || s == 'confirmed';
  }

  Future<void> _cancel() async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Cancel Order'), content: const Text('Are you sure you want to cancel this order?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, Cancel', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
      ],
    ));
    if (confirm == true) {
      await _svc.cancelOrder(widget.orderId);
      _load();
    }
  }

  Future<void> _reorder() async {
    try {
      final data = await _svc.reorder(widget.orderId);
      final cart = CartService();
      for (final item in data['items'] as List) {
        cart.addProduct(Product(
          id: item['product_id'] ?? '', name: item['name'] ?? item['product_name'] ?? '',
          category: '', brand: '', price: (item['price'] ?? 0).toDouble(),
          originalPrice: (item['price'] ?? 0).toDouble(), image: '', stock: 99, description: '',
        ), item['quantity'] ?? 1);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Items added to cart'), backgroundColor: Colors.blue));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(title: const Text('Order Details')), body: const Center(child: CircularProgressIndicator()));
    if (_error != null) return Scaffold(appBar: AppBar(title: const Text('Order Details')), body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey[400]),
      const SizedBox(height: 16),
      Text('Could not load order', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
      const SizedBox(height: 16),
      ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh, size: 18), label: const Text('Retry'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    ])));
    if (_order == null) return Scaffold(appBar: AppBar(title: const Text('Order Details')), body: const Center(child: Text('Order not found')));

    final o = _order!;
    final items = o['items'] as List? ?? [];
    final status = o['order_status'] ?? '';
    final addr = o['delivery_address'] != null ? Map<String, dynamic>.from(o['delivery_address'] as Map) : <String, dynamic>{};

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: Text('#${o['order_id']}'), centerTitle: true, elevation: 0),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Status card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _statusColor(status).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _statusColor(status).withValues(alpha: 0.3))),
          child: Row(children: [
            Icon(_statusIcon(status), size: 32, color: _statusColor(status)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(status, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _statusColor(status))),
              Text('Placed on ${(o['created_at'] ?? '').toString().split('T').first}', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ])),
            if (status != 'Cancelled' && status != 'Delivered')
              TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: widget.orderId))),
                child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Track', style: TextStyle(fontWeight: FontWeight.bold)))),
          ]),
        ),
        const SizedBox(height: 16),

        // Items
        _section('Items', items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.shopping_bag_outlined, color: Colors.grey)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item['product_name'] ?? item['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${item['quantity']} × ₹${(item['price'] ?? 0).toStringAsFixed(0)}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ])),
            Text('₹${(item['subtotal'] ?? (item['price'] ?? 0) * (item['quantity'] ?? 0)).toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
        )).toList()),
        const SizedBox(height: 12),

        // Bill
        _section('Bill Details', [
          _billRow('Subtotal (incl. GST)', '₹${(o['subtotal'] ?? 0).toStringAsFixed(2)}'),
          _billRow('GST included', '₹${(o['gst'] ?? 0).toStringAsFixed(2)}'),
          _billRow('Delivery', (o['delivery_fee'] ?? 0) == 0 ? 'FREE' : '₹${o['delivery_fee'].toStringAsFixed(0)}'),
          if ((o['discount'] ?? 0) > 0) _billRow('Discount', '-₹${o['discount'].toStringAsFixed(0)}'),
          const Divider(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('₹${(o['total_amount'] ?? o['grand_total'] ?? 0).toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)),
          ]),
        ]),
        const SizedBox(height: 12),

        // Payment & Address
        _section('Details', [
          _infoRow(Icons.payment, 'Payment', o['payment_method'] ?? 'N/A'),
          if (addr.isNotEmpty)
            _infoRow(Icons.location_on, 'Address',
                '${addr['full_name'] ?? addr['label'] ?? ''}, ${addr['line1'] ?? addr['house_no'] ?? ''}, ${addr['city'] ?? ''} - ${addr['pincode'] ?? ''}'),
          if ((o['delivery_slot'] ?? '').toString().isNotEmpty)
            _infoRow(Icons.schedule, 'Delivery Slot', o['delivery_slot']),
        ]),
        const SizedBox(height: 20),

        // Action buttons
        Row(children: [
          if (_canCancel)
            Expanded(child: SizedBox(height: 48, child: OutlinedButton(
              onPressed: _cancel,
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: const Text('Cancel Order', style: TextStyle(fontWeight: FontWeight.bold)),
            ))),
          if (_canCancel) const SizedBox(width: 12),
          Expanded(child: SizedBox(height: 48, child: ElevatedButton.icon(
            onPressed: _reorder,
            icon: const Icon(Icons.replay, size: 18),
            label: const Text('Reorder', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
          ))),
        ]),
        const SizedBox(height: 12),

        // Invoice
        SizedBox(height: 48, child: OutlinedButton.icon(
          onPressed: () async {
            final url = Uri.parse('${AppConfig.baseUrl}/orders/${widget.orderId}/invoice');
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            } else if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not open invoice'), behavior: SnackBarBehavior.floating));
            }
          },
          icon: const Icon(Icons.receipt, size: 18),
          label: const Text('Download Invoice', style: TextStyle(fontWeight: FontWeight.bold)),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.indigo, side: const BorderSide(color: Colors.indigo),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        )),
        const SizedBox(height: 24),
      ]),
    );
  }

  IconData _statusIcon(String s) => switch (s.toLowerCase()) {
    'confirmed' => Icons.check_circle, 'packed' => Icons.inventory_2,
    'out for delivery' => Icons.local_shipping, 'delivered' => Icons.done_all,
    'cancelled' => Icons.cancel, _ => Icons.receipt_long,
  };

  Widget _section(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12), ...children,
    ]),
  );

  Widget _billRow(String l, String v) => Padding(padding: const EdgeInsets.only(bottom: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: TextStyle(color: Colors.grey[600])), Text(v),
    ]));

  Widget _infoRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 20, color: Colors.grey[500]),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ]),
    ]),
  );
}
