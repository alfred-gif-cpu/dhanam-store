import 'dart:async';
import 'package:flutter/material.dart';
import '../models/product.dart';
import 'product_card.dart';

class FlashDealSection extends StatefulWidget {
  final List<Product> products;
  const FlashDealSection({super.key, required this.products});

  @override
  State<FlashDealSection> createState() => _FlashDealSectionState();
}

class _FlashDealSectionState extends State<FlashDealSection> {
  late DateTime _endTime;
  Timer? _timer;
  String _countdown = '';

  @override
  void initState() {
    super.initState();
    _endTime = DateTime.now().add(const Duration(hours: 6));
    _updateCountdown();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateCountdown());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateCountdown() {
    final diff = _endTime.difference(DateTime.now());
    if (diff.isNegative) { _timer?.cancel(); return; }
    setState(() {
      final h = diff.inHours.toString().padLeft(2, '0');
      final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
      final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
      _countdown = '$h:$m:$s';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.products.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.bolt, size: 18, color: Colors.yellow),
                SizedBox(width: 4),
                Text('Flash Deals', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ]),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
              child: Text(_countdown, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ]),
        ),
        SizedBox(
          height: 278,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: widget.products.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => SizedBox(
              width: 158,
              child: ProductCard(product: widget.products[i]),
            ),
          ),
        ),
      ],
    );
  }
}
