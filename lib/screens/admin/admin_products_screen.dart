import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../services/api_service.dart';
import '../../services/admin_service.dart';
import 'product_form_screen.dart';

class AdminProductsScreen extends StatefulWidget {
  const AdminProductsScreen({super.key});

  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> {
  final ApiService _api = ApiService();
  final AdminService _admin = AdminService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  List<Product> _products = [];
  bool _loading = true;
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final ProductResponse response;
      if (_searchQuery.isNotEmpty) {
        response = await _api.searchProducts(_searchQuery, page: _page, limit: 20);
      } else {
        response = await _api.getProducts(page: _page, limit: 20);
      }
      setState(() {
        _products = response.products;
        _totalPages = response.pages;
        _total = response.total;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() {
        _searchQuery = value.trim();
        _page = 1;
      });
      _load();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() { _searchQuery = ''; _page = 1; });
    _load();
  }

  Future<void> _delete(Product p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Product'),
        content: Text('Delete "${p.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirm == true) {
      await _admin.deleteProduct(p.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Manage Products'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductFormScreen()));
          _load();
        },
        backgroundColor: Colors.indigo,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Product', style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search products by name...',
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: _clearSearch)
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey[300]!)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.indigo, width: 2)),
              ),
            ),
          ),

          // Result count
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _loading ? 'Loading...' : '$_total products${_searchQuery.isNotEmpty ? ' matching "$_searchQuery"' : ''}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
          ),

          // Product list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _products.isEmpty
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isNotEmpty ? 'No products found for "$_searchQuery"' : 'No products',
                          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                        ),
                      ]))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _products.length,
                          itemBuilder: (context, index) {
                            final p = _products[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 50, height: 50,
                                    child: p.image.isNotEmpty
                                        ? Image.network(p.image, fit: BoxFit.cover, errorBuilder: (_, _, _) => _ph())
                                        : _ph(),
                                  ),
                                ),
                                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text('${p.category} • ₹${p.price.toStringAsFixed(0)} • Stock: ${p.stock}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (action) async {
                                    if (action == 'edit') {
                                      await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(product: p)));
                                      _load();
                                    } else if (action == 'delete') {
                                      _delete(p);
                                    } else if (action == 'feature') {
                                      final messenger = ScaffoldMessenger.of(context);
                                      await _admin.toggleFeatured(p.id, true);
                                      if (mounted) messenger.showSnackBar(const SnackBar(content: Text('Marked as featured'), behavior: SnackBarBehavior.floating));
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                                    PopupMenuItem(value: 'feature', child: Text('Mark Featured')),
                                    PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                                  ],
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            );
                          },
                        ),
                      ),
          ),

          // Pagination
          if (!_loading && _totalPages > 1)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(onPressed: _page > 1 ? () { _page--; _load(); } : null, icon: const Icon(Icons.chevron_left)),
                Text('Page $_page of $_totalPages', style: const TextStyle(fontWeight: FontWeight.w600)),
                IconButton(onPressed: _page < _totalPages ? () { _page++; _load(); } : null, icon: const Icon(Icons.chevron_right)),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _ph() => Container(width: 50, height: 50, color: Colors.grey[200], child: const Icon(Icons.image, color: Colors.grey, size: 24));
}
