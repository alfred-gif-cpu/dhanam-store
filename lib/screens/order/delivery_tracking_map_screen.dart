import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/order_service.dart';

class DeliveryTrackingMapScreen extends StatefulWidget {
  final String orderId;
  final double deliveryLat;
  final double deliveryLng;

  const DeliveryTrackingMapScreen({
    super.key,
    required this.orderId,
    required this.deliveryLat,
    required this.deliveryLng,
  });

  @override
  State<DeliveryTrackingMapScreen> createState() => _State();
}

class _State extends State<DeliveryTrackingMapScreen> {
  final MapController _mapController = MapController();
  final OrderService _svc = OrderService();

  late LatLng _deliveryLocation;
  late LatLng _storeLocation;
  late LatLng _driverLocation;
  String _status = '';
  String _partner = '';
  String _eta = '';
  Timer? _simTimer;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _deliveryLocation = LatLng(widget.deliveryLat, widget.deliveryLng);
    _storeLocation = LatLng(widget.deliveryLat + 0.015, widget.deliveryLng - 0.01);
    _driverLocation = _storeLocation;
    _loadTracking();
    _startSimulation();
  }

  @override
  void dispose() { _simTimer?.cancel(); super.dispose(); }

  Future<void> _loadTracking() async {
    try {
      final data = await _svc.trackOrder(widget.orderId);
      setState(() {
        _status = data['order_status'] ?? '';
        _partner = data['tracking']?['assigned_delivery_partner'] ?? 'Finding driver...';
        _eta = _formatEta(data['estimated_delivery'] ?? '');
      });
    } catch (_) {}
  }

  void _startSimulation() {
    _simTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_progress >= 1.0) { _simTimer?.cancel(); return; }
      setState(() {
        _progress += 0.05;
        _driverLocation = LatLng(
          _storeLocation.latitude + (_deliveryLocation.latitude - _storeLocation.latitude) * _progress,
          _storeLocation.longitude + (_deliveryLocation.longitude - _storeLocation.longitude) * _progress,
        );
      });
      _fitBounds();
    });
  }

  void _fitBounds() {
    try {
      _mapController.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(
            min(_driverLocation.latitude, min(_deliveryLocation.latitude, _storeLocation.latitude)) - 0.003,
            min(_driverLocation.longitude, min(_deliveryLocation.longitude, _storeLocation.longitude)) - 0.003,
          ),
          LatLng(
            max(_driverLocation.latitude, max(_deliveryLocation.latitude, _storeLocation.latitude)) + 0.003,
            max(_driverLocation.longitude, max(_deliveryLocation.longitude, _storeLocation.longitude)) + 0.003,
          ),
        ),
        padding: const EdgeInsets.all(60),
      ));
    } catch (_) {}
  }

  String _formatEta(String iso) {
    if (iso.isEmpty) return 'Calculating...';
    try {
      final dt = DateTime.parse(iso);
      final diff = dt.difference(DateTime.now());
      if (diff.isNegative) return 'Arriving now';
      if (diff.inMinutes < 60) return '${diff.inMinutes} min';
      return '${diff.inHours}h ${diff.inMinutes % 60}m';
    } catch (_) { return 'Soon'; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(
                (_storeLocation.latitude + _deliveryLocation.latitude) / 2,
                (_storeLocation.longitude + _deliveryLocation.longitude) / 2,
              ),
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.dhanam.store',
              ),
              PolylineLayer(polylines: [
                Polyline(points: [_storeLocation, _driverLocation], color: Colors.blue, strokeWidth: 4,
                    pattern: const StrokePattern.dashed(segments: [10, 6])),
                Polyline(points: [_driverLocation, _deliveryLocation], color: Colors.green, strokeWidth: 4),
              ]),
              MarkerLayer(markers: [
                Marker(point: _storeLocation, width: 40, height: 40,
                    child: const Icon(Icons.store, size: 36, color: Colors.orange)),
                Marker(point: _deliveryLocation, width: 44, height: 44,
                    child: const Icon(Icons.location_pin, size: 44, color: Colors.green)),
                Marker(point: _driverLocation, width: 44, height: 44,
                    child: Container(
                      decoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.blue.withValues(alpha: 0.4), blurRadius: 12, spreadRadius: 3)]),
                      child: const Icon(Icons.delivery_dining, size: 26, color: Colors.white),
                    )),
              ]),
            ],
          ),

          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8, left: 12,
            child: CircleAvatar(backgroundColor: Colors.white,
              child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black87), onPressed: () => Navigator.pop(context))),
          ),

          // Legend
          Positioned(
            top: MediaQuery.of(context).padding.top + 8, right: 12,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6)]),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                _legend(Colors.orange, 'Store'),
                const SizedBox(height: 4),
                _legend(Colors.blue, 'Driver'),
                const SizedBox(height: 4),
                _legend(Colors.green, 'You'),
              ]),
            ),
          ),

          // Bottom panel
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, -4))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // ETA
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.green[700]!, Colors.green[400]!]),
                    borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    const Icon(Icons.schedule, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Estimated Arrival', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Text(_eta.isNotEmpty ? _eta : 'Calculating...', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    ])),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                      child: Text(_status, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),

                // Driver
                Row(children: [
                  CircleAvatar(backgroundColor: Colors.blue[50], radius: 24,
                      child: Icon(Icons.delivery_dining, color: Colors.blue[700], size: 24)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Delivery Partner', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(_partner.isNotEmpty ? _partner : 'Assigning...', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ])),
                  Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.green[50], shape: BoxShape.circle),
                    child: Icon(Icons.phone, color: Colors.green[700], size: 22)),
                ]),
                const SizedBox(height: 12),

                // Progress
                ClipRRect(borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: _progress.clamp(0.0, 1.0), minHeight: 6,
                    backgroundColor: Colors.grey[200], valueColor: AlwaysStoppedAnimation(Colors.green[600]!))),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Dhanam Store', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  Text('Your Location', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ]),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 6),
    Text(label, style: const TextStyle(fontSize: 11)),
  ]);
}
