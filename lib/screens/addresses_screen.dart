import 'package:flutter/material.dart';
import '../models/address.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'map_picker_screen.dart';

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key});

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  final ApiService _api = ApiService();
  List<Address> _addresses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final addrs = await _api.getAddresses(AuthService().userId);
      setState(() { _addresses = addrs; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  void _showAddDialog() {
    final name = TextEditingController();
    final phone = TextEditingController();
    final line1 = TextEditingController();
    final city = TextEditingController();
    final state = TextEditingController();
    final pincode = TextEditingController();
    String label = 'Home';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Add Address', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: label,
            items: ['Home', 'Work', 'Other'].map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
            onChanged: (v) => label = v!,
            decoration: const InputDecoration(labelText: 'Label', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: line1, decoration: const InputDecoration(labelText: 'Address Line', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          SizedBox(height: 44, child: OutlinedButton.icon(
            onPressed: () async {
              final result = await Navigator.push<Map<String, dynamic>>(ctx, MaterialPageRoute(builder: (_) => const MapPickerScreen()));
              if (result != null) line1.text = result['address'] ?? '';
            },
            icon: const Icon(Icons.map, size: 18),
            label: const Text('Pick on Map'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.green, side: const BorderSide(color: Colors.green),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          )),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: city, decoration: const InputDecoration(labelText: 'City', border: OutlineInputBorder()))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: state, decoration: const InputDecoration(labelText: 'State', border: OutlineInputBorder()))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: pincode, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pincode', border: OutlineInputBorder())),
          const SizedBox(height: 20),
          SizedBox(height: 50, child: ElevatedButton(
            onPressed: () async {
              if (name.text.isEmpty || phone.text.isEmpty || line1.text.isEmpty || city.text.isEmpty || pincode.text.isEmpty) return;
              await _api.addAddress(AuthService().userId, {
                'label': label, 'full_name': name.text, 'phone': phone.text,
                'line1': line1.text, 'city': city.text, 'state': state.text, 'pincode': pincode.text,
              });
              if (ctx.mounted) Navigator.pop(ctx);
              _load();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: const Text('Save Address', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          )),
        ])),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: const Text('My Addresses'), centerTitle: true, elevation: 0),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: Colors.green,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add New', style: TextStyle(color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _addresses.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.location_off, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('No addresses saved', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _addresses.length,
                  itemBuilder: (context, index) {
                    final addr = _addresses[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        Icon(addr.label == 'Work' ? Icons.work_outline : Icons.home_outlined, color: Colors.green[700]),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(addr.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(addr.fullName, style: const TextStyle(fontSize: 14)),
                          Text(addr.shortAddress, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                          Text(addr.phone, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                        ])),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: Colors.red[400]),
                          onPressed: () async {
                            await _api.deleteAddress(addr.id);
                            _load();
                          },
                        ),
                      ]),
                    );
                  },
                ),
    );
  }
}
