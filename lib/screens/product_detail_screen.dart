import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../services/recently_viewed_service.dart';
import '../services/review_service.dart';
import '../services/wishlist_service.dart';
import '../widgets/product_image.dart';
import 'cart_screen.dart';

class ProductDetailScreen extends StatefulWidget {
  final Product product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int _quantity = 1;
  final WishlistService _wishlist = WishlistService();
  final CartService _cart = CartService();
  final ApiService _api = ApiService();
  final ReviewService _reviewService = ReviewService();
  List<Product> _related = [];
  List<dynamic> _reviews = [];
  Map<String, dynamic> _reviewStats = {};
  bool _reviewsLoading = true;

  Product get product => widget.product;

  @override
  void initState() {
    super.initState();
    _wishlist.addListener(_refresh);
    _cart.addListener(_refresh);
    RecentlyViewedService().add(product.id);
    _loadRelated();
    _loadReviews();
    // Dismiss any leftover SnackBar from the previous product page —
    // SnackBars anchor to the root Navigator's overlay, so a message
    // shown just before navigating here (e.g. "Added ... to cart" on a
    // related product) would otherwise keep floating over this screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    });
  }

  @override
  void dispose() {
    _wishlist.removeListener(_refresh);
    _cart.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  Future<void> _loadReviews() async {
    try {
      final data = await _reviewService.getProductReviews(product.id);
      if (mounted) {
        setState(() {
          _reviews = data['reviews'] ?? [];
          _reviewStats = data['stats'] ?? {};
          _reviewsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _reviewsLoading = false);
    }
  }

  Future<void> _showWriteReviewDialog() async {
    int selectedRating = 5;
    final titleCtrl = TextEditingController();
    final commentCtrl = TextEditingController();

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Text('Write a Review', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text('Rating', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: List.generate(5, (i) => GestureDetector(
                  onTap: () => setSheetState(() => selectedRating = i + 1),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      i < selectedRating ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 36,
                      color: i < selectedRating ? Colors.amber : Colors.grey[300],
                    ),
                  ),
                )),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(
                  hintText: 'Review title (optional)',
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Share your experience...',
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text('Submit Review', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (submitted == true) {
      try {
        final auth = AuthService();
        await _reviewService.submitReview(
          productId: product.id,
          userId: auth.userId,
          userName: auth.name.trim().isNotEmpty ? auth.name.trim() : 'Customer',
          rating: selectedRating,
          title: titleCtrl.text.trim(),
          comment: commentCtrl.text.trim(),
        );
        _loadReviews();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Review submitted!'), backgroundColor: Colors.blue),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to submit: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
    titleCtrl.dispose();
    commentCtrl.dispose();
  }

  Future<void> _loadRelated() async {
    try {
      final response = await _api.getProducts(category: product.category, limit: 10);
      setState(() {
        _related = response.products.where((p) => p.id != product.id).toList();
      });
    } catch (_) {}
  }

  void _addToCart() {
    _cart.addProduct(product, _quantity);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Added $_quantity × ${product.name} to cart'),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      action: SnackBarAction(label: 'UNDO', textColor: Colors.yellow, onPressed: () => _cart.remove(product.id)),
    ));
  }

  void _buyNow() {
    _cart.addProduct(product, _quantity);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          // Collapsing app bar with hero image
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            elevation: 0,
            actions: [
              IconButton(
                icon: Icon(
                  _wishlist.isWishlisted(product.id) ? Icons.favorite : Icons.favorite_outline,
                  color: _wishlist.isWishlisted(product.id) ? Colors.red : Colors.grey[700],
                ),
                onPressed: () => _wishlist.toggle(product),
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined),
                onPressed: () {
                  final text = StringBuffer('Check out ${product.name}');
                  if (product.hasDiscount) {
                    text.write(' - ${product.discountPercent}% OFF!');
                  }
                  text.write('\n₹${product.price.toStringAsFixed(0)}');
                  if (product.hasDiscount) {
                    text.write(' (was ₹${product.originalPrice.toStringAsFixed(0)})');
                  }
                  text.write('\n\nShop now on Dhanam Stores!');
                  SharePlus.instance.share(ShareParams(text: text.toString()));
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'product-image-${product.id}',
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(24),
                      child: ProductImage(
                        imageUrl: product.image,
                        category: product.category,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  if (product.hasDiscount)
                    Positioned(
                      top: 100,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${product.discountPercent}% OFF',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Main info card
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category + Brand row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(20)),
                    child: Text(product.category, style: TextStyle(fontSize: 12, color: Colors.blue[700], fontWeight: FontWeight.w600)),
                  ),
                  if (product.brand.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(20)),
                      child: Text(product.brand, style: TextStyle(fontSize: 12, color: Colors.blue[700], fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),

              // Name
              Text(product.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, height: 1.2)),
              const SizedBox(height: 16),

              // Price section
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₹${product.price.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue)),
                  if (product.hasDiscount) ...[
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('₹${product.originalPrice.toStringAsFixed(0)}',
                          style: TextStyle(fontSize: 18, color: Colors.grey[400], decoration: TextDecoration.lineThrough)),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(6)),
                        child: Text('Save ₹${(product.originalPrice - product.price).toStringAsFixed(0)}',
                            style: TextStyle(fontSize: 12, color: Colors.blue[700], fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // Stock + delivery
              Row(
                children: [
                  _infoPill(
                    icon: product.inStock ? Icons.check_circle : Icons.cancel,
                    color: product.inStock ? Colors.blue : Colors.red,
                    text: product.inStock ? '${product.stock} in stock' : 'Out of stock',
                  ),
                  const SizedBox(width: 12),
                  _infoPill(icon: Icons.bolt, color: Colors.orange, text: '10 min delivery'),
                ],
              ),
            ],
          ),
        ),

        // Quantity selector card
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              const Text('Quantity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    _qtyButton(Icons.remove, _quantity > 1 ? () => setState(() => _quantity--) : null),
                    GestureDetector(
                      onTap: () => _editQuantity(product),
                      child: SizedBox(
                        width: 44,
                        child: Text('$_quantity', textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.dotted)),
                      ),
                    ),
                    _qtyButton(Icons.add, _quantity < product.stock ? () => setState(() => _quantity++) : null),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Text('₹${(product.price * _quantity).toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
            ],
          ),
        ),

        // Description
        if (product.description.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.grey),
                    SizedBox(width: 6),
                    Text('Product Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(product.description, style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.6)),
              ],
            ),
          ),

        // Ratings & Reviews
        _buildReviewsSection(),

        // Related products
        if (_related.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Text('You might also like', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          SizedBox(
            height: 220,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _related.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => _RelatedCard(
                product: _related[index],
                onTap: () {
                  Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: _related[index])));
                },
              ),
            ),
          ),
        ],

        const SizedBox(height: 120),
      ],
    );
  }

  Widget _buildReviewsSection() {
    final avgRating = (_reviewStats['avg_rating'] ?? 0).toDouble();
    final totalReviews = (_reviewStats['count'] ?? 0) as int;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Ratings & Reviews', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: _showWriteReviewDialog,
                icon: const Icon(Icons.rate_review_outlined, size: 18),
                label: const Text('Write'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_reviewsLoading)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2)))
          else if (totalReviews == 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    Icon(Icons.rate_review_outlined, size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 8),
                    Text('No reviews yet', style: TextStyle(fontSize: 15, color: Colors.grey[500])),
                    const SizedBox(height: 4),
                    Text('Be the first to review this product', style: TextStyle(fontSize: 13, color: Colors.grey[400])),
                  ],
                ),
              ),
            )
          else ...[
            // Summary row
            Row(
              children: [
                Column(
                  children: [
                    Text(avgRating.toStringAsFixed(1), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
                    Row(
                      children: List.generate(5, (i) => Icon(
                        i < avgRating.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 18, color: Colors.amber,
                      )),
                    ),
                    const SizedBox(height: 4),
                    Text('$totalReviews reviews', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                  ],
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    children: List.generate(5, (i) {
                      final star = 5 - i;
                      final count = (_reviewStats['r$star'] ?? 0) as int;
                      final pct = totalReviews > 0 ? count / totalReviews : 0.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Text('$star', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: pct,
                                  backgroundColor: Colors.grey[200],
                                  color: Colors.amber,
                                  minHeight: 8,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(width: 24, child: Text('$count', style: TextStyle(fontSize: 11, color: Colors.grey[500]))),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
            const Divider(height: 28),

            // Review list
            ...(_reviews.take(3).map((r) => _buildReviewCard(r))),
            if (_reviews.length > 3)
              Center(
                child: TextButton(
                  onPressed: () {},
                  child: Text('View all $totalReviews reviews', style: TextStyle(color: Colors.blue[700])),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    final rating = (review['rating'] ?? 0) as int;
    final name = review['user_name'] ?? 'Customer';
    final title = review['title'] ?? '';
    final comment = review['comment'] ?? '';
    final date = review['created_at'] ?? '';
    final helpful = (review['helpful_count'] ?? 0) as int;

    String displayDate = '';
    if (date.isNotEmpty) {
      try {
        final dt = DateTime.parse(date);
        final diff = DateTime.now().difference(dt);
        if (diff.inDays == 0) {
          displayDate = 'Today';
        } else if (diff.inDays == 1) {
          displayDate = 'Yesterday';
        } else if (diff.inDays < 30) {
          displayDate = '${diff.inDays} days ago';
        } else {
          displayDate = '${dt.day}/${dt.month}/${dt.year}';
        }
      } catch (_) {}
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: Colors.blue[50], shape: BoxShape.circle),
                child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'C',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[700]))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(displayDate, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: rating >= 4 ? Colors.blue : rating >= 3 ? Colors.amber : Colors.red,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$rating', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                    const Icon(Icons.star_rounded, size: 14, color: Colors.white),
                  ],
                ),
              ),
            ],
          ),
          if (title.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ],
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(comment, style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.4)),
          ],
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              await _reviewService.markHelpful(review['id']);
              _loadReviews();
            },
            child: Row(
              children: [
                Icon(Icons.thumb_up_outlined, size: 14, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text('Helpful${helpful > 0 ? ' ($helpful)' : ''}', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, -4))],
      ),
      child: Row(
        children: [
          // Add to Cart
          Expanded(
            child: SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: product.inStock ? _addToCart : null,
                icon: const Icon(Icons.shopping_cart_outlined, size: 20),
                label: const Text('Add to Cart', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                  side: const BorderSide(color: Colors.blue, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Buy Now
          Expanded(
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: product.inStock ? _buyNow : null,
                icon: const Icon(Icons.bolt, size: 20),
                label: const Text('Buy Now', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoPill({required IconData icon, required Color color, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Icon(icon, size: 20, color: onTap != null ? Colors.black87 : Colors.grey[400]),
      ),
    );
  }

  Future<void> _editQuantity(Product product) async {
    final controller = TextEditingController(text: '$_quantity');
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
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
    if (result != null && result > 0) {
      setState(() => _quantity = result.clamp(1, maxQty));
    }
  }
}

class _RelatedCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _RelatedCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 130,
                    width: 140,
                    child: ProductImage(imageUrl: product.image, category: product.category, fit: BoxFit.cover),
                  ),
                ),
                if (product.hasDiscount)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                      child: Text('${product.discountPercent}%', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Row(
              children: [
                Text('₹${product.price.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue)),
                if (product.hasDiscount) ...[
                  const SizedBox(width: 4),
                  Text('₹${product.originalPrice.toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 10, color: Colors.grey[400], decoration: TextDecoration.lineThrough)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
