import 'package:flutter/material.dart';
import '../models/product.dart';
import 'product_card.dart';

class HorizontalProductList extends StatelessWidget {
  final List<Product> products;
  const HorizontalProductList({super.key, required this.products});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 278,
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
