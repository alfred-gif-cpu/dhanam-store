import 'package:flutter/material.dart';
import '../../services/order_service.dart';
import 'delivery_tracking_map_screen.dart';

class OrderTrackingScreen extends StatefulWidget {
  final String orderId;
  const OrderTrackingScreen({super.key, required this.orderId});

  @override
  State<OrderTrackingScreen> createState() => _State();
}

class _State extends State<OrderTrackingScreen> with SingleTickerProviderStateMixin {
  final OrderService _svc = OrderService();
  Map<String, dynamic>? _tracking;
  bool _loading = true;
  late AnimationController _pulseController;

  static const _steps = ['Pending', 'Confirmed', 'Packed', 'Out For Delivery', 'Delivered'];
  static const _icons = [Icons.receipt_long, Icons.check_circle, Icons.inventory_2, Icons.local_shipping, Icons.done_all];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _load();
  }

  @override
  void dispose() { _pulseController.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final data = await _svc.trackOrder(widget.orderId);
      setState(() { _tracking = data; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  int get _currentStep {
    final status = _tracking?['order_status'] ?? '';
    final idx = _steps.indexWhere((s) => s.toLowerCase() == status.toLowerCase());
    return idx >= 0 ? idx : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: Text('Track #${widget.orderId}'), centerTitle: true, elevation: 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tracking == null
              ? const Center(child: Text('Tracking unavailable'))
              : ListView(padding: const EdgeInsets.all(20), children: [
                  // ETA card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Colors.blue[700]!, Colors.blue[400]!]),
                      borderRadius: BorderRadius.circular(20)),
                    child: Row(children: [
                      const Icon(Icons.schedule, color: Colors.white, size: 32),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Estimated Delivery', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(_formatEta(_tracking?['estimated_delivery'] ?? ''),
                            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      ])),
                    ]),
                  ),
                  const SizedBox(height: 12),

                  // Live map button
                  SizedBox(
                    width: double.infinity, height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => DeliveryTrackingMapScreen(
                          orderId: widget.orderId,
                          deliveryLat: 12.7409,
                          deliveryLng: 77.8253,
                        ),
                      )),
                      icon: const Icon(Icons.map, size: 20),
                      label: const Text('View Live on Map', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue, foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Delivery partner
                  if ((_tracking?['tracking']?['assigned_delivery_partner'] ?? '').toString().isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 20), padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        CircleAvatar(backgroundColor: Colors.blue[50], child: Icon(Icons.delivery_dining, color: Colors.blue[700])),
                        const SizedBox(width: 12),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Delivery Partner', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          Text(_tracking!['tracking']['assigned_delivery_partner'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ]),
                      ]),
                    ),

                  // Timeline
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Order Timeline', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 20),
                        ...List.generate(_steps.length, (i) => _timelineStep(i)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Status history
                  if ((_tracking?['status_history'] as List?)?.isNotEmpty == true)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Status Updates', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        ...(_tracking!['status_history'] as List).reversed.map((h) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            Icon(Icons.circle, size: 8, color: Colors.blue[400]),
                            const SizedBox(width: 10),
                            Expanded(child: Text(h['status'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500))),
                            Text(_formatTimestamp(h['timestamp'] ?? ''), style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                          ]),
                        )),
                      ]),
                    ),
                ]),
    );
  }

  Widget _timelineStep(int index) {
    final done = index <= _currentStep;
    final active = index == _currentStep;
    final isLast = index == _steps.length - 1;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dot + line
        SizedBox(
          width: 32,
          child: Column(children: [
            active
                ? AnimatedBuilder(
                    animation: _pulseController,
                    builder: (_, __) => Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue,
                        boxShadow: [BoxShadow(color: Colors.blue.withValues(alpha: 0.3 + _pulseController.value * 0.3), blurRadius: 8, spreadRadius: 2)],
                      ),
                      child: const Icon(Icons.circle, size: 12, color: Colors.white),
                    ),
                  )
                : Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? Colors.blue : Colors.grey[300],
                      border: done ? null : Border.all(color: Colors.grey[400]!, width: 2),
                    ),
                    child: done ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                  ),
            if (!isLast) Container(width: 3, height: 48, color: done ? Colors.blue : Colors.grey[300]),
          ]),
        ),
        const SizedBox(width: 14),
        // Content
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(_icons[index], size: 20, color: done ? Colors.blue[700] : Colors.grey[400]),
                const SizedBox(width: 8),
                Text(_steps[index], style: TextStyle(
                  fontSize: 15, fontWeight: done ? FontWeight.bold : FontWeight.normal,
                  color: done ? Colors.black87 : Colors.grey[500])),
              ]),
              if (active)
                Padding(padding: const EdgeInsets.only(top: 4),
                  child: Text('In progress...', style: TextStyle(fontSize: 12, color: Colors.blue[600]))),
            ]),
          ),
        ),
      ],
    );
  }

  String _formatEta(String iso) {
    if (iso.isEmpty) return 'Calculating...';
    try {
      final dt = DateTime.parse(iso);
      final diff = dt.difference(DateTime.now());
      if (diff.isNegative) return 'Any moment now';
      if (diff.inMinutes < 60) return '${diff.inMinutes} mins';
      return '${diff.inHours}h ${diff.inMinutes % 60}m';
    } catch (_) { return iso.split('T').first; }
  }

  String _formatTimestamp(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return iso; }
  }
}
