import 'package:flutter/material.dart';
import '../../services/customer_service.dart';

class CustomerWalletScreen extends StatefulWidget {
  const CustomerWalletScreen({super.key});

  @override
  State<CustomerWalletScreen> createState() => _State();
}

class _State extends State<CustomerWalletScreen> {
  final CustomerService _cs = CustomerService();
  List<dynamic> _txns = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _cs.addListener(_r); _load(); }
  @override
  void dispose() { _cs.removeListener(_r); super.dispose(); }
  void _r() => setState(() {});

  Future<void> _load() async {
    try {
      final data = await _cs.getWalletTransactions();
      setState(() { _txns = data['transactions'] ?? []; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  void _showTopUp() {
    final controller = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Add Money'),
      content: TextField(controller: controller, keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Amount (₹)', prefixText: '₹ ', border: OutlineInputBorder())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () async {
          final amount = double.tryParse(controller.text) ?? 0;
          if (amount > 0) { await _cs.walletCredit(amount); _load(); }
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Add', style: TextStyle(fontWeight: FontWeight.bold))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: const Text('Wallet'), centerTitle: true, elevation: 0),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.blue[700]!, Colors.blue[400]!]),
            borderRadius: BorderRadius.circular(20)),
          child: Column(children: [
            const Text('Wallet Balance', style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 8),
            Text('₹${_cs.walletBalance.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(height: 42, child: ElevatedButton.icon(
              onPressed: _showTopUp,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Money', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.blue[700],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
            )),
          ]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: const Align(alignment: Alignment.centerLeft, child: Text('Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))),
        Expanded(
          child: _loading ? const Center(child: CircularProgressIndicator())
              : _txns.isEmpty
                  ? Center(child: Text('No transactions yet', style: TextStyle(color: Colors.grey[600])))
                  : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: _txns.length,
                      itemBuilder: (_, i) {
                        final t = _txns[i] as Map<String, dynamic>;
                        final isCredit = t['type'] == 'credit';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                          child: Row(children: [
                            Container(padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: (isCredit ? Colors.green : Colors.red).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                              child: Icon(isCredit ? Icons.arrow_downward : Icons.arrow_upward, color: isCredit ? Colors.green : Colors.red, size: 20)),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(t['reason'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text((t['created_at'] ?? '').toString().split('T').first, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                            ])),
                            Text('${isCredit ? '+' : '-'}₹${(t['amount'] ?? 0).toStringAsFixed(0)}',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isCredit ? Colors.green : Colors.red)),
                          ]),
                        );
                      }),
        ),
      ]),
    );
  }
}
