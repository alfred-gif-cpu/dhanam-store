import 'package:flutter/material.dart';
import '../models/product.dart';
import '../screens/product_detail_screen.dart';
import '../services/wishlist_service.dart';
import '../services/cart_service.dart';
import 'product_image.dart';

class ProductCard extends StatefulWidget {
  final Product product;

  const ProductCard({super.key, required this.product});

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  final WishlistService _wishlist = WishlistService();
  final CartService _cart = CartService();

  static const _green = Color(0xFF0C831F);

  @override
  void initState() {
    super.initState();
    _wishlist.addListener(_refresh);
    _cart.addListener(_refresh);
  }

  @override
  void dispose() {
    _wishlist.removeListener(_refresh);
    _cart.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() { if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final wishlisted = _wishlist.isWishlisted(product.id);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8E8E8)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Image area ───
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: const Color(0xFFF7F7F7),
                    padding: const EdgeInsets.all(8),
                    child: Hero(
                      tag: 'product-image-${product.id}',
                      child: ProductImage(
                        imageUrl: product.image,
                        category: product.category,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  // Discount badge (angled corner ribbon style)
                  if (product.hasDiscount)
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: const BoxDecoration(
                          color: Color(0xFF1976D2),
                          borderRadius: BorderRadius.only(bottomRight: Radius.circular(8)),
                        ),
                        child: Text('${product.discountPercent}% OFF',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                  // Wishlist heart
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _wishlist.toggle(product),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)],
                        ),
                        child: Icon(
                          wishlisted ? Icons.favorite : Icons.favorite_outline,
                          size: 16,
                          color: wishlisted ? Colors.red : Colors.grey[500],
                        ),
                      ),
                    ),
                  ),
                  if (!product.inStock)
                    Positioned.fill(
                      child: Container(
                        color: Colors.white70,
                        child: const Center(
                          child: Text('Out of Stock',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red)),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ─── Details ───
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Delivery-time chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.bolt, size: 11, color: Colors.grey[700]),
                      const SizedBox(width: 2),
                      Text('10 MINS',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.grey[700])),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  Text(product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.2)),
                  const SizedBox(height: 2),
                  Text(product.brand.isNotEmpty ? product.brand : product.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  const SizedBox(height: 8),
                  // Price + ADD button row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('₹${product.price.toStringAsFixed(0)}',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                            if (product.hasDiscount)
                              Text('₹${product.originalPrice.toStringAsFixed(0)}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[400],
                                      decoration: TextDecoration.lineThrough)),
                          ],
                        ),
                      ),
                      if (product.inStock) _addButton(product),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addButton(Product product) {
    final qty = _cart.quantityOf(product.id);
    if (qty == 0) {
      return SizedBox(
        height: 34,
        child: OutlinedButton(
          onPressed: () => _cart.addProduct(product, 1),
          style: OutlinedButton.styleFrom(
            foregroundColor: _green,
            backgroundColor: const Color(0xFFF3FBF4),
            side: const BorderSide(color: _green, width: 1.3),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('ADD', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ),
      );
    }
    return Container(
      height: 34,
      decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          _stepBtn(Icons.remove, () => _cart.decrement(product.id)),
          GestureDetector(
            onTap: () => _editQuantity(product),
            child: Container(
              constraints: const BoxConstraints(minWidth: 20),
              alignment: Alignment.center,
              child: Text('$qty',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
          _stepBtn(Icons.add, () => _cart.increment(product.id)),
        ],
      ),
    );
  }

  Future<void> _editQuantity(Product product) async {
    final controller = TextEditingController(text: '${_cart.quantityOf(product.id)}');
    final maxQty = product.stock > 0 ? product.stock : 1;
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Enter quantity'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'AppSans'),
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            helperText: 'Max $maxQty available',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (result != null) _cart.updateQuantity(product.id, result.clamp(0, maxQty));
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }
}
