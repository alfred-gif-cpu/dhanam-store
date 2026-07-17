import 'package:flutter/material.dart';
import '../models/product.dart';
import 'product_card.dart';

class HorizontalProductList extends StatelessWidget {
  final List<Product> products;
  const HorizontalProductList({super.key, required this.products});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Tall enough for a 2-line product name plus the price+ADD row at the
      // 158px card width — 278 clipped the bottom row by ~16px when a name
      // wrapped to two lines (e.g. "Ambika Appalam No.6").
      height: 296,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: products.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return SizedBox(
            width: 158,
            child: ProductCard(product: products[index]),
          );
        },
      ),
    );
  }
}
