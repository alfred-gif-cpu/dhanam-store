import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

class MapPickerScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;

  const MapPickerScreen({super.key, this.initialLat, this.initialLng});

  @override
  State<MapPickerScreen> createState() => _State();
}

class _State extends State<MapPickerScreen> {
  final MapController _mapController = MapController();
  // Default to Chennai
  LatLng _selectedLocation = const LatLng(12.7409, 77.8253);
  String _address = 'Tap on the map to select location';
  bool _geocoding = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialLat != null && widget.initialLng != null) {
      _selectedLocation = LatLng(widget.initialLat!, widget.initialLng!);
      _reverseGeocode(_selectedLocation);
    }
  }

  Future<void> _reverseGeocode(LatLng loc) async {
    setState(() => _geocoding = true);
    try {
      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?lat=${loc.latitude}&lon=${loc.longitude}&format=json&addressdetails=1');
      final res = await http.get(url, headers: {'User-Agent': 'DhanamStore/1.0'});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final display = data['display_name'] ?? '';
        if (display.toString().isNotEmpty) {
          setState(() => _address = display);
        }
      }
    } catch (_) {
      setState(() => _address = '${loc.latitude.toStringAsFixed(5)}, ${loc.longitude.toStringAsFixed(5)}');
    }
    setState(() => _geocoding = false);
  }

  void _onTap(TapPosition _, LatLng position) {
    setState(() => _selectedLocation = position);
    _reverseGeocode(position);
  }

  void _confirm() {
    Navigator.pop(context, {
      'lat': _selectedLocation.latitude,
      'lng': _selectedLocation.longitude,
      'address': _address,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Delivery Location'),
        centerTitle: true, elevation: 0,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedLocation,
              initialZoom: 15,
              onTap: _onTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.dhanam.store',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _selectedLocation,
                    width: 50, height: 50,
                    child: const Icon(Icons.location_pin, size: 50, color: Colors.green),
                  ),
                ],
              ),
            ],
          ),

          // Address panel
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, -4))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Icon(Icons.location_on, color: Colors.green[700], size: 24),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Delivery Location', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 2),
                    _geocoding
                        ? Text('Finding address...', style: TextStyle(color: Colors.grey[500]))
                        : Text(_address, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ])),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: _geocoding ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green, foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                    child: const Text('Confirm Location', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
