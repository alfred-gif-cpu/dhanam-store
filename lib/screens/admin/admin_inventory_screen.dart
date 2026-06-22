import 'package:flutter/material.dart';
import '../../services/admin_auth_service.dart';

class AdminInventoryScreen extends StatefulWidget {
  const AdminInventoryScreen({super.key});

  @override
  State<AdminInventoryScreen> createState() => _State();
}

class _State extends State<AdminInventoryScreen> {
  final AdminAuthService _auth = AdminAuthService();
  List<dynamic> _items = [];
  bool _loading = true;
  int _total = 0;
  String _filter = '';
  final _filters = {'': 'All', 'low': 'Low Stock', 'out': 'Out of Stock', 'in': 'In Stock'};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _auth.getInventory(filter: _filter);
      setState(() { _items = data['items']; _total = data['total']; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  void _showUpdateDialog(Map<String, dynamic> item) {
    final controller = TextEditingController(text: '${item['stock']}');
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Update Stock: ${item['name']}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Current stock: ${item['stock']}', style: TextStyle(color: Colors.grey[600])),
        const SizedBox(height: 12),
        TextField(controller: controller, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'New Stock Quantity', border: OutlineInputBorder())),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () async {
          final stock = int.tryParse(controller.text) ?? 0;
          await _auth.updateStock(item['id'], stock);
          if (ctx.mounted) Navigator.pop(ctx);
          _load();
        }, child: const Text('Update', style: TextStyle(fontWeight: FontWeight.bold))),
      ],
    ));
  }

  void _showReceiveDialog(Map<String, dynamic> item) {
    final controller = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Receive Stock: ${item['name']}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Current stock: ${item['stock']}', style: TextStyle(color: Colors.grey[600])),
        const SizedBox(height: 12),
        TextField(controller: controller, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Quantity Received', border: OutlineInputBorder())),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () async {
          final qty = int.tryParse(controller.text) ?? 0;
          if (qty > 0) await _auth.receiveStock(item['id'], qty);
          if (ctx.mounted) Navigator.pop(ctx);
          _load();
        }, child: const Text('Receive', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
      ],
    ));
  }

  Color _stockColor(int stock) => stock == 0 ? Colors.red : stock < 10 ? Colors.orange : Colors.blue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(title: Text('Inventory ($_total)'), backgroundColor: Colors.indigo[800], foregroundColor: Colors.white, elevation: 0),
      body: Column(children: [
        SizedBox(height: 50, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: _filters.entries.map((e) {
            final sel = _filter == e.key;
            return Padding(padding: const EdgeInsets.only(right: 8), child: FilterChip(
              label: Text(e.value, style: TextStyle(fontSize: 12, color: sel ? Colors.white : Colors.grey[700])),
              selected: sel, onSelected: (_) { _filter = sel ? '' : e.key; _load(); },
              selectedColor: Colors.indigo, checkmarkColor: Colors.white, backgroundColor: Colors.white,
              side: BorderSide(color: sel ? Colors.indigo : Colors.grey[300]!),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ));
          }).toList(),
        )),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(onRefresh: _load, child: ListView.builder(
                padding: const EdgeInsets.all(12), itemCount: _items.length,
                itemBuilder: (_, i) {
                  final item = _items[i] as Map<String, dynamic>;
                  final stock = item['stock'] as int? ?? 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                      border: stock == 0 ? Border.all(color: Colors.red.withValues(alpha: 0.3)) : null),
                    child: ListTile(
                      title: Text(item['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${item['category']} • ₹${(item['price'] ?? 0).toStringAsFixed(0)}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: _stockColor(stock).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text('$stock', style: TextStyle(fontWeight: FontWeight.bold, color: _stockColor(stock))),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'update') _showUpdateDialog(item);
                            if (action == 'receive') _showReceiveDialog(item);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'update', child: Text('Set Stock')),
                            PopupMenuItem(value: 'receive', child: Text('Receive Stock')),
                          ],
                        ),
                      ]),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  );
                }))),
      ]),
    );
  }
}
