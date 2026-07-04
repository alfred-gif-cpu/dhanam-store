import 'package:flutter/material.dart';
import '../models/product.dart';
import '../widgets/product_card.dart';

/// Generic grid screen for showing a full list of products under a title —
/// used by "View All" / section header taps (Flash Deals, Featured, etc.)
class ProductListScreen extends StatelessWidget {
  final String title;
  final List<Product> products;

  const ProductListScreen({super.key, required this.title, required this.products});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: Text(title), centerTitle: true, elevation: 0),
      body: products.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text('No products found', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
              ]),
            )
          : LayoutBuilder(builder: (context, constraints) {
              final cols = constraints.maxWidth > 900 ? 4 : constraints.maxWidth > 600 ? 3 : 2;
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: products.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols, childAspectRatio: 0.568, crossAxisSpacing: 10, mainAxisSpacing: 10),
                itemBuilder: (context, index) => ProductCard(product: products[index]),
              );
            }),
    );
  }
}
