import 'package:flutter/material.dart';
import '../../models/address.dart';
import '../../services/address_service.dart';
import '../../services/auth_service.dart';
import 'address_form_screen.dart';

class AddressListScreen extends StatefulWidget {
  final bool pickMode;
  const AddressListScreen({super.key, this.pickMode = false});

  @override
  State<AddressListScreen> createState() => _State();
}

class _State extends State<AddressListScreen> {
  final AddressService _svc = AddressService();
  List<Address> _addresses = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final addrs = await _svc.getAddresses(AuthService().userId);
      setState(() { _addresses = addrs; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _delete(Address addr) async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Delete Address'),
      content: Text('Delete "${addr.label}" address at ${addr.shortAddress}?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
      ],
    ));
    if (confirm == true) {
      await _svc.deleteAddress(addr.id);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Address deleted'), behavior: SnackBarBehavior.floating));
      }
    }
  }

  Future<void> _setDefault(Address addr) async {
    await _svc.setDefault(addr.id);
    _load();
  }

  IconData _labelIcon(String label) => switch (label.toLowerCase()) {
    'work' => Icons.work_outlined,
    'other' => Icons.location_on_outlined,
    _ => Icons.home_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(widget.pickMode ? 'Select Address' : 'My Addresses'),
        centerTitle: true, elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressFormScreen()));
          _load();
        },
        backgroundColor: Colors.blue,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Address', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _addresses.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    itemCount: _addresses.length,
                    itemBuilder: (_, i) => _buildCard(_addresses[i]),
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 100, height: 100,
          decoration: BoxDecoration(color: Colors.blue[50], shape: BoxShape.circle),
          child: Icon(Icons.location_off, size: 48, color: Colors.blue[300]),
        ),
        const SizedBox(height: 24),
        const Text('No saved addresses', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Add a delivery address to get started', style: TextStyle(fontSize: 15, color: Colors.grey[500])),
      ]),
    ));
  }

  Widget _buildCard(Address addr) {
    return GestureDetector(
      onTap: widget.pickMode ? () => Navigator.pop(context, addr) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16),
          border: addr.isDefault ? Border.all(color: Colors.blue, width: 2) : null,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Icon
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: addr.isDefault ? Colors.blue[50] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12)),
                child: Icon(_labelIcon(addr.label), color: addr.isDefault ? Colors.blue[700] : Colors.grey[600]),
              ),
              const SizedBox(width: 12),

              // Details
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(addr.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  if (addr.isDefault) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                      child: Text('Default', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue[700])),
                    ),
                  ],
                ]),
                const SizedBox(height: 6),
                Text(addr.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(addr.fullAddress, style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.4)),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.phone, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(addr.phone, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  if (addr.hasCoordinates) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.gps_fixed, size: 14, color: Colors.blue[400]),
                    const SizedBox(width: 4),
                    Text('GPS saved', style: TextStyle(fontSize: 12, color: Colors.blue[500])),
                  ],
                ]),
              ])),

              // Menu
              PopupMenuButton<String>(
                onSelected: (action) async {
                  if (action == 'edit') {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => AddressFormScreen(address: addr)));
                    _load();
                  }
                  if (action == 'default') _setDefault(addr);
                  if (action == 'delete') _delete(addr);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Row(children: [
                    Icon(Icons.edit, size: 18, color: Colors.indigo), SizedBox(width: 8), Text('Edit')])),
                  if (!addr.isDefault)
                    const PopupMenuItem(value: 'default', child: Row(children: [
                      Icon(Icons.star, size: 18, color: Colors.orange), SizedBox(width: 8), Text('Set as Default')])),
                  const PopupMenuItem(value: 'delete', child: Row(children: [
                    Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: Colors.red))])),
                ],
              ),
            ]),
          ),

          // Quick action buttons
          if (!widget.pickMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(children: [
                _actionBtn(Icons.edit, 'Edit', Colors.indigo, () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => AddressFormScreen(address: addr)));
                  _load();
                }),
                const SizedBox(width: 8),
                if (!addr.isDefault)
                  _actionBtn(Icons.star_border, 'Set Default', Colors.orange, () => _setDefault(addr)),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }
}
