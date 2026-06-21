import 'package:flutter/material.dart';
import '../models/banner.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../services/cart_service.dart';
import '../services/recently_viewed_service.dart';
import '../services/wishlist_service.dart';
import '../widgets/banner_carousel.dart';
import '../widgets/category_carousel.dart';
import '../widgets/flash_deal_card.dart';
import '../widgets/horizontal_product_list.dart';
import '../widgets/product_card.dart';
import '../widgets/section_header.dart';
import '../widgets/shimmer_loading.dart';
import 'cart_screen.dart';
import 'browse_screen.dart';
import 'search_screen.dart';
import 'wishlist_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static void switchTab(int index) => _HomeScreenState.switchTab(index);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static _HomeScreenState? _instance;
  int _navIndex = 0;
  final WishlistService _wishlist = WishlistService();

  static void switchTab(int index) => _instance?.setState(() => _instance!._navIndex = index);

  @override
  void initState() {
    super.initState();
    _instance = this;
    _wishlist.addListener(_refresh);
  }

  @override
  void dispose() {
    if (_instance == this) _instance = null;
    _wishlist.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final screens = [
      const _HomeTab(),
      const BrowseScreen(),
      const WishlistScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _navIndex, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _navIndex,
        onTap: (i) => setState(() => _navIndex = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
          const BottomNavigationBarItem(icon: Icon(Icons.grid_view_outlined), activeIcon: Icon(Icons.grid_view), label: 'Browse'),
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: _wishlist.count > 0,
              label: Text('${_wishlist.count}', style: const TextStyle(fontSize: 10)),
              backgroundColor: Colors.red,
              child: const Icon(Icons.favorite_outline),
            ),
            activeIcon: Badge(
              isLabelVisible: _wishlist.count > 0,
              label: Text('${_wishlist.count}', style: const TextStyle(fontSize: 10)),
              backgroundColor: Colors.red,
              child: const Icon(Icons.favorite),
            ),
            label: 'Wishlist',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class _HomeTab extends StatefulWidget {
  const _HomeTab();

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> with AutomaticKeepAliveClientMixin {
  final ApiService _api = ApiService();
  final CartService _cart = CartService();
  final RecentlyViewedService _recentService = RecentlyViewedService();

  List<HomeBanner> _banners = [];
  List<Category> _categories = [];
  List<Product> _featured = [];
  List<Product> _bestsellers = [];
  List<Product> _flashDeals = [];
  List<Product> _trending = [];
  List<Product> _recentlyViewed = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cart.addListener(_refresh);
    _recentService.addListener(_loadRecentlyViewed);
    _loadAll();
  }

  @override
  void dispose() {
    _cart.removeListener(_refresh);
    _recentService.removeListener(_loadRecentlyViewed);
    super.dispose();
  }

  void _refresh() => setState(() {});

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getBanners(),
        _api.getCategories(),
        _api.getFeaturedProducts(),
        _api.getBestsellers(),
        _api.getFlashDeals(),
        _api.getTrending(),
      ]);
      setState(() {
        _banners = results[0] as List<HomeBanner>;
        _categories = results[1] as List<Category>;
        _featured = results[2] as List<Product>;
        _bestsellers = results[3] as List<Product>;
        _flashDeals = results[4] as List<Product>;
        _trending = results[5] as List<Product>;
        _loading = false;
      });
      _loadRecentlyViewed();
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadRecentlyViewed() async {
    if (_recentService.ids.isEmpty) return;
    try {
      final products = await _api.getProductsByIds(_recentService.ids.take(10).toList());
      if (mounted) setState(() => _recentlyViewed = products);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            floating: true,
            snap: true,
            elevation: 0,
            backgroundColor: Colors.white,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Dhanam Store', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                Row(children: [
                  Icon(Icons.bolt, size: 14, color: Colors.green[700]),
                  const SizedBox(width: 2),
                  Text('Delivery in 10 mins', style: TextStyle(fontSize: 12, color: Colors.green[700])),
                ]),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.search, color: Colors.black87),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
              ),
              Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.shopping_cart_outlined, color: Colors.black87),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())),
                  ),
                  if (_cart.itemCount > 0)
                    Positioned(
                      top: 6, right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        child: Text('${_cart.itemCount}',
                            style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
        body: _loading
            ? const ShimmerLoading()
            : RefreshIndicator(
                onRefresh: _loadAll,
                child: ListView(
                  children: [
                    const SizedBox(height: 8),

                    // Banners
                    BannerCarousel(banners: _banners),

                    // Categories
                    if (_categories.isNotEmpty) ...[
                      const SectionHeader(title: 'Shop by Category'),
                      CategoryCarousel(
                        categories: _categories,
                        onTap: (cat) {
                          final homeState = context.findAncestorStateOfType<_HomeScreenState>();
                          if (homeState != null) homeState.setState(() => homeState._navIndex = 1);
                        },
                      ),
                    ],

                    // Flash deals with timer
                    if (_flashDeals.isNotEmpty) FlashDealSection(products: _flashDeals),

                    // Featured
                    if (_featured.isNotEmpty) ...[
                      const SectionHeader(title: 'Featured Products'),
                      HorizontalProductList(products: _featured),
                    ],

                    // Trending
                    if (_trending.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(children: [
                          Icon(Icons.trending_up, size: 22, color: Colors.orange[700]),
                          const SizedBox(width: 6),
                          const Text('Trending Now', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                      HorizontalProductList(products: _trending),
                    ],

                    // Best sellers grid
                    if (_bestsellers.isNotEmpty) ...[
                      const SectionHeader(title: 'Best Sellers'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _bestsellers.length > 6 ? 6 : _bestsellers.length,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2, childAspectRatio: 0.72, crossAxisSpacing: 10, mainAxisSpacing: 10),
                          itemBuilder: (_, i) => ProductCard(product: _bestsellers[i]),
                        ),
                      ),
                    ],

                    // Recently viewed
                    if (_recentlyViewed.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                        child: Row(children: [
                          Icon(Icons.history, size: 22, color: Colors.grey[600]),
                          const SizedBox(width: 6),
                          const Text('Recently Viewed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                      HorizontalProductList(products: _recentlyViewed),
                    ],

                    // Bottom padding
                    const SizedBox(height: 30),
                  ],
                ),
              ),
      ),
    );
  }
}
