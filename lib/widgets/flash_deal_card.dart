import 'dart:async';
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../screens/product_detail_screen.dart';
import '../services/cart_service.dart';
import 'product_image.dart';

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
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: widget.products.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _FlashCard(product: widget.products[i]),
          ),
        ),
      ],
    );
  }
}

class _FlashCard extends StatelessWidget {
  final Product product;
  const _FlashCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product))),
      child: Container(
        width: 145,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                child: SizedBox.expand(child: ProductImage(imageUrl: product.image, category: product.category)),
              ),
              if (product.hasDiscount)
                Positioned(top: 6, left: 6, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                  child: Text('${product.discountPercent}% OFF', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                )),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Row(children: [
              Text('₹${product.price.toStringAsFixed(0)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue)),
              if (product.hasDiscount) ...[
                const SizedBox(width: 4),
                Text('₹${product.originalPrice.toStringAsFixed(0)}', style: TextStyle(fontSize: 10, color: Colors.grey[400], decoration: TextDecoration.lineThrough)),
              ],
            ]),
          ),
          // Quick add button
          GestureDetector(
            onTap: () {
              CartService().addProduct(product, 1);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('${product.name} added to cart'), behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 1)));
            },
            child: Container(
              margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue[300]!)),
              child: Text('ADD', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue[700])),
            ),
          ),
        ]),
      ),
    );
  }
}
