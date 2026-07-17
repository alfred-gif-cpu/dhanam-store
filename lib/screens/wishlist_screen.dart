import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/cart_service.dart';
import '../services/wishlist_service.dart';
import '../widgets/product_image.dart';
import 'home_screen.dart';
import 'product_detail_screen.dart';

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  final WishlistService _wishlist = WishlistService();
  final CartService _cart = CartService();

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

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(_wishlist.isEmpty ? 'My Wishlist' : 'My Wishlist (${_wishlist.count})'),
        centerTitle: true,
        elevation: 0,
      ),
      body: _wishlist.isEmpty ? _buildEmpty() : _buildList(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
              child: Icon(Icons.favorite_outline, size: 56, color: Colors.red[200]),
            ),
            const SizedBox(height: 24),
            const Text('Your wishlist is empty', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Save items you love by tapping the\nheart icon on any product',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey[500], height: 1.5),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 50,
              width: 200,
              child: ElevatedButton.icon(
                onPressed: () => HomeScreen.switchTab(1),
                icon: const Icon(Icons.shopping_bag_outlined),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Explore Products', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _wishlist.items.length,
      itemBuilder: (context, index) {
        final product = _wishlist.items[index];
        return Dismissible(
          key: ValueKey('wish-${product.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Colors.red[400], borderRadius: BorderRadius.circular(16)),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delete_outline, color: Colors.white, size: 24),
                SizedBox(height: 2),
                Text('Remove', style: TextStyle(color: Colors.white, fontSize: 11)),
              ],
            ),
          ),
          onDismissed: (_) => _wishlist.toggle(product),
          child: _WishlistItemCard(
            product: product,
            cart: _cart,
            onRemove: () => _wishlist.toggle(product),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product))),
          ),
        );
      },
    );
  }
}

class _WishlistItemCard extends StatefulWidget {
  final Product product;
  final CartService cart;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  const _WishlistItemCard({
    required this.product,
    required this.cart,
    required this.onRemove,
    required this.onTap,
  });

  @override
  State<_WishlistItemCard> createState() => _WishlistItemCardState();
}

class _WishlistItemCardState extends State<_WishlistItemCard> {
  // Local quantity chosen before adding — like the product detail page, so
  // the user picks a count and then presses a persistent "Add to Cart"
  // button, rather than the button turning into a live stepper.
  int _qty = 1;

  Product get product => widget.product;
  CartService get cart => widget.cart;

  int get _maxQty => product.stock > 0 ? product.stock : 1;

  Future<void> _editQuantity() async {
    final controller = TextEditingController(text: '$_qty');
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
            helperText: 'Max $_maxQty available',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)), child: const Text('OK')),
        ],
      ),
    );
    if (result != null) setState(() => _qty = result.clamp(1, _maxQty));
  }

  void _addToCart() {
    final prev = cart.quantityOf(product.id);
    cart.addProduct(product, _qty);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Added $_qty × ${product.name} to cart'),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      action: SnackBarAction(
        label: 'UNDO',
        textColor: Colors.yellow,
        onPressed: () => cart.updateQuantity(product.id, prev),
      ),
    ));
  }

  Widget _qtySelector() {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _qty > 1 ? () => setState(() => _qty--) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Icon(Icons.remove, size: 16, color: _qty > 1 ? Colors.blue[700] : Colors.grey[300]),
            ),
          ),
          GestureDetector(
            onTap: _editQuantity,
            child: Container(
              constraints: const BoxConstraints(minWidth: 26),
              alignment: Alignment.center,
              child: Text('$_qty', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blue[800])),
            ),
          ),
          InkWell(
            onTap: _qty < _maxQty ? () => setState(() => _qty++) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Icon(Icons.add, size: 16, color: _qty < _maxQty ? Colors.blue[700] : Colors.grey[300]),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            // Image
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 88,
                height: 88,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: 'product-image-${product.id}',
                      child: ProductImage(imageUrl: product.image, category: product.category),
                    ),
                    if (product.hasDiscount)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                          child: Text('${product.discountPercent}%', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  if (product.brand.isNotEmpty)
                    Text(product.brand, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  const SizedBox(height: 6),
                  // Price row
                  Row(
                    children: [
                      Text('₹${product.price.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
                      if (product.hasDiscount) ...[
                        const SizedBox(width: 6),
                        Text('₹${product.originalPrice.toStringAsFixed(0)}',
                            style: TextStyle(fontSize: 13, color: Colors.grey[400], decoration: TextDecoration.lineThrough)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Pick a quantity, then a persistent "Add to Cart" button
                  // commits that count (matches the product detail page).
                  if (product.inStock) ...[
                    _qtySelector(),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 34,
                          child: ElevatedButton.icon(
                            onPressed: product.inStock ? _addToCart : null,
                            icon: const Icon(Icons.shopping_cart_outlined, size: 16),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(product.inStock ? 'Add to Cart' : 'Out of Stock', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey[200],
                              disabledForegroundColor: Colors.grey[500],
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 34,
                        width: 34,
                        child: IconButton.outlined(
                          onPressed: widget.onRemove,
                          icon: const Icon(Icons.close, size: 16),
                          padding: EdgeInsets.zero,
                          style: IconButton.styleFrom(
                            side: BorderSide(color: Colors.grey[300]!),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
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
}
