import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../services/cart_service.dart';
import '../services/recently_viewed_service.dart';
import '../services/review_service.dart';
import '../services/search_history_service.dart';
import '../services/wishlist_service.dart';
import '../widgets/horizontal_product_list.dart';
import '../widgets/product_image.dart';
import 'cart_screen.dart';
import 'search_screen.dart';

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
  final RecentlyViewedService _recentService = RecentlyViewedService();
  final SearchHistoryService _searchHistory = SearchHistoryService();
  List<Product> _related = [];
  List<Product> _recentlyViewed = [];
  List<dynamic> _reviews = [];
  Map<String, dynamic> _reviewStats = {};
  bool _reviewsLoading = true;
  bool _canReview = false;

  Product get product => widget.product;

  @override
  void initState() {
    super.initState();
    _wishlist.addListener(_refresh);
    _cart.addListener(_refresh);
    _recentService.add(product.id);
    _loadRelated();
    _loadReviews();
    _loadCanReview();
    _loadRecentlyViewed();
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
    // SnackBars are shown via the app-wide ScaffoldMessenger, so by default
    // one triggered here (e.g. "Added to cart") keeps floating on top of
    // whatever screen comes next instead of disappearing when this page is
    // left. Clear it explicitly so it doesn't bleed into other screens.
    ScaffoldMessenger.of(context).clearSnackBars();
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

  Future<void> _loadCanReview() async {
    final eligible = await _reviewService.canReview(product.id);
    if (mounted) setState(() => _canReview = eligible);
  }

  static const int _minReviewLength = 10;

  void _showCannotReviewMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'You can write a review once this product has been delivered to you',
        ),
      ),
    );
  }

  Future<void> _showWriteReviewDialog() async {
    int selectedRating = 5;
    final titleCtrl = TextEditingController();
    final commentCtrl = TextEditingController();
    String? commentError;

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Write a Review',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Rating',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                children: List.generate(
                  5,
                  (i) => GestureDetector(
                    onTap: () => setSheetState(() => selectedRating = i + 1),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        i < selectedRating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 36,
                        color: i < selectedRating
                            ? Colors.amber
                            : Colors.grey[300],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(
                  hintText: 'Review title (optional)',
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentCtrl,
                maxLines: 3,
                onChanged: (_) {
                  if (commentError != null) {
                    setSheetState(() => commentError = null);
                  }
                },
                decoration: InputDecoration(
                  hintText:
                      'Share your experience (min $_minReviewLength characters)...',
                  filled: true,
                  fillColor: Colors.grey[100],
                  errorText: commentError,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    final text = commentCtrl.text.trim();
                    if (text.length < _minReviewLength) {
                      setSheetState(
                        () => commentError =
                            'Please write at least $_minReviewLength characters describing your experience',
                      );
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Submit Review',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (submitted == true) {
      try {
        await _reviewService.submitReview(
          productId: product.id,
          rating: selectedRating,
          title: titleCtrl.text.trim(),
          comment: commentCtrl.text.trim(),
        );
        _loadReviews();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Review submitted!'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to submit: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
    titleCtrl.dispose();
    commentCtrl.dispose();
  }

  Future<void> _loadRelated() async {
    try {
      final response = await _api.getProducts(
        category: product.category,
        limit: 10,
      );
      setState(() {
        _related = response.products.where((p) => p.id != product.id).toList();
      });
    } catch (_) {}
  }

  Future<void> _loadRecentlyViewed() async {
    // Exclude the product on screen — it was just added to the front of
    // this same list a moment ago in initState.
    final ids = _recentService.ids
        .where((id) => id != product.id)
        .take(10)
        .toList();
    if (ids.isEmpty) return;
    try {
      final products = await _api.getProductsByIds(ids);
      if (mounted) setState(() => _recentlyViewed = products);
    } catch (_) {}
  }

  bool get _inCart => _cart.quantityOf(product.id) > 0;

  void _toggleCart() {
    if (_inCart) {
      _cart.remove(product.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${product.name} removed from cart'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } else {
      _cart.addProduct(product, _quantity);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added $_quantity × ${product.name} to cart'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  void _buyNow() {
    _cart.addProduct(product, _quantity);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CartScreen()),
    );
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
                  _wishlist.isWishlisted(product.id)
                      ? Icons.favorite
                      : Icons.favorite_outline,
                  color: _wishlist.isWishlisted(product.id)
                      ? Colors.red
                      : Colors.grey[700],
                ),
                onPressed: () => _wishlist.toggle(product),
              ),
              IconButton(
                icon: Badge(
                  isLabelVisible: _cart.itemCount > 0,
                  label: Text(
                    '${_cart.itemCount}',
                    style: const TextStyle(fontSize: 10),
                  ),
                  backgroundColor: Colors.red,
                  child: const Icon(Icons.shopping_cart_outlined),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CartScreen()),
                ),
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
                    text.write(
                      ' (was ₹${product.originalPrice.toStringAsFixed(0)})',
                    );
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${product.discountPercent}% OFF',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
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
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category + Brand row
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      product.category,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (product.brand.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        product.brand,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // Name
              Text(
                product.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 16),

              // Price section
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${product.price.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  if (product.hasDiscount) ...[
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '₹${product.originalPrice.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[400],
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Save ₹${(product.originalPrice - product.price).toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // Stock + delivery
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _infoPill(
                    icon: product.inStock ? Icons.check_circle : Icons.cancel,
                    color: product.inStock ? Colors.blue : Colors.red,
                    text: product.inStock
                        ? '${product.stock} in stock'
                        : 'Out of stock',
                  ),
                  _infoPill(
                    icon: Icons.bolt,
                    color: Colors.orange,
                    text: '10 min delivery',
                  ),
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
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const Text(
                'Quantity',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    _qtyButton(
                      Icons.remove,
                      _quantity > 1 ? () => setState(() => _quantity--) : null,
                    ),
                    GestureDetector(
                      onTap: () => _editQuantity(product),
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[100]!),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$_quantity',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.edit, size: 13, color: Colors.blue[400]),
                          ],
                        ),
                      ),
                    ),
                    _qtyButton(
                      Icons.add,
                      _quantity < product.stock
                          ? () => setState(() => _quantity++)
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '₹${(product.price * _quantity).toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
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
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.grey),
                    SizedBox(width: 6),
                    Text(
                      'Product Details',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  product.description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),

        // Ratings & Reviews
        _buildReviewsSection(),

        // Related products — reuse the shared HorizontalProductList /
        // ProductCard (same as "Recently Viewed") so the cards render
        // correctly instead of the old fixed-height custom card that clipped.
        if (_related.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Text(
              'You might also like',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          HorizontalProductList(products: _related),
        ],

        // Recent searches
        if (_searchHistory.history.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Text(
              'Recent searches by you',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _searchHistory.history
                  .map(
                    (query) => GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SearchScreen(initialQuery: query),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.history,
                              size: 15,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 6),
                            Text(query, style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],

        // Recently viewed products
        if (_recentlyViewed.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Text(
              'Recently Viewed',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          HorizontalProductList(products: _recentlyViewed),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  'Ratings & Reviews',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton.icon(
                onPressed: _canReview
                    ? _showWriteReviewDialog
                    : _showCannotReviewMessage,
                icon: Icon(
                  Icons.rate_review_outlined,
                  size: 18,
                  color: _canReview ? null : Colors.grey[400],
                ),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Write',
                    style: TextStyle(
                      color: _canReview ? null : Colors.grey[400],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_reviewsLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (totalReviews == 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    Icon(
                      Icons.rate_review_outlined,
                      size: 48,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No reviews yet',
                      style: TextStyle(fontSize: 15, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Be the first to review this product',
                      style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                    ),
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
                    Text(
                      avgRating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: List.generate(
                        5,
                        (i) => Icon(
                          i < avgRating.round()
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 18,
                          color: Colors.amber,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$totalReviews reviews',
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
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
                            Text(
                              '$star',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: Colors.amber,
                            ),
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
                            SizedBox(
                              width: 24,
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ),
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
                  child: Text(
                    'View all $totalReviews reviews',
                    style: TextStyle(color: Colors.blue[700]),
                  ),
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'C',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      displayDate,
                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: rating >= 4
                      ? Colors.blue
                      : rating >= 3
                      ? Colors.amber
                      : Colors.red,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$rating',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Icon(
                      Icons.star_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (title.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              comment,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              await _reviewService.markHelpful(review['id']);
              _loadReviews();
            },
            child: Row(
              children: [
                Icon(
                  Icons.thumb_up_outlined,
                  size: 14,
                  color: Colors.grey[400],
                ),
                const SizedBox(width: 4),
                Text(
                  'Helpful${helpful > 0 ? ' ($helpful)' : ''}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Add to Cart / Remove from Cart (toggles based on cart state)
          Expanded(
            child: SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: product.inStock ? _toggleCart : null,
                icon: Icon(
                  _inCart
                      ? Icons.remove_shopping_cart_outlined
                      : Icons.shopping_cart_outlined,
                  size: 20,
                ),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _inCart ? 'Remove from Cart' : 'Add to Cart',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _inCart ? Colors.red : Colors.blue,
                  side: BorderSide(
                    color: _inCart ? Colors.red : Colors.blue,
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
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
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Buy Now',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoPill({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
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
        child: Icon(
          icon,
          size: 20,
          color: onTap != null ? Colors.black87 : Colors.grey[400],
        ),
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
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            fontFamily: 'AppSans',
          ),
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            helperText: 'Max $maxQty available',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
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

