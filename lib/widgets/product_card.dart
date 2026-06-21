import 'package:flutter/material.dart';
import '../models/product.dart';
import '../screens/product_detail_screen.dart';
import '../services/wishlist_service.dart';
import 'product_image.dart';

class ProductCard extends StatefulWidget {
  final Product product;

  const ProductCard({super.key, required this.product});

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> with SingleTickerProviderStateMixin {
  final WishlistService _wishlist = WishlistService();
  late AnimationController _heartAnim;

  @override
  void initState() {
    super.initState();
    _wishlist.addListener(_refresh);
    _heartAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  }

  @override
  void dispose() {
    _wishlist.removeListener(_refresh);
    _heartAnim.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _toggleWishlist() {
    _wishlist.toggle(widget.product);
    if (_wishlist.isWishlisted(widget.product.id)) {
      _heartAnim.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final wishlisted = _wishlist.isWishlisted(product.id);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)),
      ),
      child: Card(
        elevation: 2,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'product-image-${product.id}',
                    child: ProductImage(imageUrl: product.image, category: product.category),
                  ),
                  // Wishlist heart
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: _toggleWishlist,
                      child: ScaleTransition(
                        scale: Tween(begin: 1.0, end: 1.3).animate(
                          CurvedAnimation(parent: _heartAnim, curve: Curves.elasticOut),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
                          ),
                          child: Icon(
                            wishlisted ? Icons.favorite : Icons.favorite_outline,
                            size: 18,
                            color: wishlisted ? Colors.red : Colors.grey[500],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Discount badge
                  if (product.hasDiscount)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                        child: Text('${product.discountPercent}% OFF',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                  // Out of stock overlay
                  if (!product.inStock)
                    Positioned.fill(
                      child: Container(
                        color: Colors.white70,
                        child: const Center(
                          child: Text('Out of Stock', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
              child: Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(product.brand.isNotEmpty ? product.brand : product.category,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  Text('₹${product.price.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green)),
                  if (product.hasDiscount) ...[
                    const SizedBox(width: 4),
                    Text('₹${product.originalPrice.toStringAsFixed(0)}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[400], decoration: TextDecoration.lineThrough)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
