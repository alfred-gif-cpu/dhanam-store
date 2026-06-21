import 'package:flutter/material.dart';
import '../../services/customer_service.dart';

class CustomerLoyaltyScreen extends StatefulWidget {
  const CustomerLoyaltyScreen({super.key});

  @override
  State<CustomerLoyaltyScreen> createState() => _State();
}

class _State extends State<CustomerLoyaltyScreen> {
  final CustomerService _cs = CustomerService();

  @override
  void initState() { super.initState(); _cs.addListener(_r); }
  @override
  void dispose() { _cs.removeListener(_r); super.dispose(); }
  void _r() => setState(() {});

  void _showRedeem() {
    final controller = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Redeem Points'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Available: ${_cs.loyaltyPoints} points', style: TextStyle(color: Colors.grey[600])),
        const SizedBox(height: 8),
        Text('100 points = ₹10 discount', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        const SizedBox(height: 12),
        TextField(controller: controller, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Points to redeem', border: OutlineInputBorder())),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () async {
          final pts = int.tryParse(controller.text) ?? 0;
          if (pts > 0 && pts <= _cs.loyaltyPoints) { await _cs.redeemLoyaltyPoints(pts); }
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('Redeem', style: TextStyle(fontWeight: FontWeight.bold))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final pts = _cs.loyaltyPoints;
    final nextTier = pts < 500 ? 'Silver' : pts < 2000 ? 'Gold' : 'Platinum';
    final nextAt = pts < 500 ? 500 : pts < 2000 ? 2000 : 5000;
    final progress = pts / nextAt;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: const Text('Loyalty Points'), centerTitle: true, elevation: 0),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.orange[700]!, Colors.amber[400]!]),
            borderRadius: BorderRadius.circular(20)),
          child: Column(children: [
            const Icon(Icons.stars, size: 48, color: Colors.white),
            const SizedBox(height: 12),
            Text('$pts', style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold)),
            const Text('Loyalty Points', style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 16),
            SizedBox(height: 42, child: ElevatedButton(
              onPressed: pts > 0 ? _showRedeem : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.orange[700],
                disabledBackgroundColor: Colors.white38, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
              child: const Text('Redeem Points', style: TextStyle(fontWeight: FontWeight.bold)),
            )),
          ]),
        ),
        const SizedBox(height: 20),

        // Tier progress
        Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Next tier: $nextTier', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('$pts / $nextAt points', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 12),
            ClipRRect(borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: progress.clamp(0.0, 1.0), minHeight: 8, backgroundColor: Colors.grey[200], valueColor: AlwaysStoppedAnimation(Colors.orange[600]!))),
          ]),
        ),
        const SizedBox(height: 20),

        // How to earn
        const Text('How to earn points', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _earnTile(Icons.shopping_bag, 'Shop', '1 point per ₹10 spent'),
        _earnTile(Icons.rate_review, 'Review', '5 points per product review'),
        _earnTile(Icons.person_add, 'Refer', '50 points per referral'),
        _earnTile(Icons.cake, 'Birthday', 'Double points on your birthday'),
      ]),
    );
  }

  Widget _earnTile(IconData icon, String title, String desc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: Colors.orange[700], size: 22)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ])),
      ]),
    );
  }
}
