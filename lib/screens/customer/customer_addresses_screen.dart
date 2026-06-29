import 'package:flutter/material.dart';
import '../../services/customer_service.dart';

class CustomerAddressesScreen extends StatefulWidget {
  const CustomerAddressesScreen({super.key});

  @override
  State<CustomerAddressesScreen> createState() => _State();
}

class _State extends State<CustomerAddressesScreen> {
  final CustomerService _cs = CustomerService();

  @override
  void initState() { super.initState(); _cs.addListener(_r); }
  @override
  void dispose() { _cs.removeListener(_r); super.dispose(); }
  void _r() => setState(() {});

  void _showForm({Map<String, dynamic>? existing}) {
    final house = TextEditingController(text: existing?['house_no'] ?? '');
    final street = TextEditingController(text: existing?['street'] ?? '');
    final city = TextEditingController(text: existing?['city'] ?? '');
    final state = TextEditingController(text: existing?['state'] ?? '');
    final pincode = TextEditingController(text: existing?['pincode'] ?? '');
    String label = existing?['label'] ?? 'Home';

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(existing != null ? 'Edit Address' : 'Add Address', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: label, items: ['Home', 'Work', 'Other'].map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
            onChanged: (v) => label = v!, decoration: const InputDecoration(labelText: 'Label', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: house, decoration: const InputDecoration(labelText: 'House/Flat No.', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: street, decoration: const InputDecoration(labelText: 'Street/Area', border: OutlineInputBorder())),
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
              if (house.text.isEmpty || street.text.isEmpty || city.text.isEmpty || pincode.text.isEmpty) return;
              final data = {'label': label, 'house_no': house.text, 'street': street.text, 'city': city.text, 'state': state.text, 'pincode': pincode.text};
              if (existing != null) {
                await _cs.editAddress(existing['id'], data);
              } else {
                await _cs.addAddress(data);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: Text(existing != null ? 'Update' : 'Save Address', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          )),
        ])),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final addrs = _cs.addresses;
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: const Text('My Addresses'), centerTitle: true, elevation: 0),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(), backgroundColor: Colors.blue,
        icon: const Icon(Icons.add, color: Colors.white), label: const Text('Add New', style: TextStyle(color: Colors.white))),
      body: addrs.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.location_off, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text('No addresses saved', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(16), itemCount: addrs.length,
              itemBuilder: (_, i) {
                final a = addrs[i] as Map<String, dynamic>;
                final isDefault = a['is_default'] == true;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(14),
                    border: isDefault ? Border.all(color: Colors.blue, width: 2) : null),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(a['label'] == 'Work' ? Icons.work_outline : Icons.home_outlined, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Text(a['label'] ?? 'Home', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      if (isDefault) ...[
                        const SizedBox(width: 8),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(6)),
                          child: Text('Default', style: TextStyle(fontSize: 10, color: Colors.blue[700], fontWeight: FontWeight.w600))),
                      ],
                      const Spacer(),
                      PopupMenuButton<String>(
                        onSelected: (action) async {
                          if (action == 'edit') _showForm(existing: a);
                          if (action == 'default') await _cs.setDefaultAddress(a['id']);
                          if (action == 'delete') await _cs.deleteAddress(a['id']);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('Edit')),
                          if (!isDefault) const PopupMenuItem(value: 'default', child: Text('Set as Default')),
                          const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text('${a['house_no']}, ${a['street']}', style: const TextStyle(fontSize: 14)),
                    Text('${a['city']}, ${a['state']} - ${a['pincode']}', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  ]),
                );
              }),
    );
  }
}
