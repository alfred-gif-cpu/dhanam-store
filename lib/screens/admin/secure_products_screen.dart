import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/admin_auth_service.dart';

class SecureProductsScreen extends StatefulWidget {
  const SecureProductsScreen({super.key});

  @override
  State<SecureProductsScreen> createState() => _State();
}

class _State extends State<SecureProductsScreen> {
  final AdminAuthService _auth = AdminAuthService();
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  List<dynamic> _products = [];
  bool _loading = true;
  int _total = 0;
  int _page = 1;
  int _pages = 1;
  String _query = '';

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _debounce?.cancel(); _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _auth.getProducts(page: _page, q: _query);
      setState(() {
        _products = data['products'] ?? [];
        _total = data['total'] ?? 0;
        _pages = data['pages'] ?? 1;
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() { _query = v.trim(); _page = 1; });
      _load();
    });
  }

  void _showAddEditForm({Map<String, dynamic>? product}) {
    final isEdit = product != null;
    final name = TextEditingController(text: product?['name'] ?? '');
    final brand = TextEditingController(text: product?['brand'] ?? '');
    final price = TextEditingController(text: product != null ? '${product['price'] ?? 0}' : '');
    final mrp = TextEditingController(text: product != null && (product['original_price'] ?? 0) > 0 ? '${product['original_price']}' : '');
    final stock = TextEditingController(text: product != null ? '${product['stock'] ?? 0}' : '');
    final description = TextEditingController(text: product?['description'] ?? '');
    String category = product?['category'] ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ProductForm(
        isEdit: isEdit,
        productId: product?['id'],
        name: name, brand: brand, price: price, mrp: mrp, stock: stock, description: description,
        category: category,
        onSave: (data) async {
          try {
            if (isEdit) {
              await _auth.putAdmin('/admin/products/${product['id']}', data);
            } else {
              await _auth.postAdmin('/admin/products', data);
            }
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(isEdit ? 'Product updated' : 'Product added'),
              backgroundColor: Colors.blue, behavior: SnackBarBehavior.floating));
            }
          } catch (e) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
          }
        },
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> product) async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Delete Product'),
      content: Text('Delete "${product['name']}"?\nThis cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
      ],
    ));
    if (confirm == true) {
      try {
        await _auth.deleteAdmin('/admin/products/${product['id']}');
        _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${product['name']} deleted'), behavior: SnackBarBehavior.floating));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('Products ($_total)'),
        backgroundColor: Colors.indigo[800], foregroundColor: Colors.white, elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditForm(),
        backgroundColor: Colors.indigo,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Product', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(children: [
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _search, onChanged: _onSearch,
            decoration: InputDecoration(
              hintText: 'Search products by name, brand, category...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _search.clear(); _onSearch(''); })
                  : null,
              filled: true, fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.indigo, width: 2)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Align(alignment: Alignment.centerLeft,
            child: Text(_loading ? 'Loading...' : '$_total products${_query.isNotEmpty ? ' matching "$_query"' : ''}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
        ),

        // List
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _products.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.inventory_2, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text('No products found', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                    ]))
                  : RefreshIndicator(onRefresh: _load, child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                      itemCount: _products.length,
                      itemBuilder: (_, i) {
                        final p = _products[i] as Map<String, dynamic>;
                        final stockVal = p['stock'] ?? 0;
                        final stockColor = stockVal == 0 ? Colors.red : (stockVal as int) < 10 ? Colors.orange : Colors.blue;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _showAddEditForm(product: p),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(children: [
                                // Image
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: 56, height: 56,
                                    child: (p['image'] ?? '').toString().isNotEmpty
                                        ? Image.network(p['image'], fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) => _placeholder())
                                        : _placeholder(),
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Details
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(p['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 2),
                                  Text('${p['category'] ?? ''}${(p['brand'] ?? '').toString().isNotEmpty ? ' • ${p['brand']}' : ''}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Row(children: [
                                    Text('₹${(p['price'] ?? 0).toStringAsFixed(0)}',
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
                                    if ((p['original_price'] ?? 0) > (p['price'] ?? 0)) ...[
                                      const SizedBox(width: 6),
                                      Text('₹${p['original_price'].toStringAsFixed(0)}',
                                          style: TextStyle(fontSize: 12, color: Colors.grey[400], decoration: TextDecoration.lineThrough)),
                                    ],
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: stockColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                      child: Text('Stock: $stockVal', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: stockColor)),
                                    ),
                                  ]),
                                ])),
                                const SizedBox(width: 8),

                                // Actions
                                Column(mainAxisSize: MainAxisSize.min, children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 20, color: Colors.indigo),
                                    onPressed: () => _showAddEditForm(product: p),
                                    padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete, size: 20, color: Colors.red[400]),
                                    onPressed: () => _delete(p),
                                    padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                  ),
                                ]),
                              ]),
                            ),
                          ),
                        );
                      })),
        ),

        // Pagination
        if (!_loading && _pages > 1)
          Container(
            padding: const EdgeInsets.all(8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(onPressed: _page > 1 ? () { _page--; _load(); } : null, icon: const Icon(Icons.chevron_left)),
              Text('$_page / $_pages', style: const TextStyle(fontWeight: FontWeight.w600)),
              IconButton(onPressed: _page < _pages ? () { _page++; _load(); } : null, icon: const Icon(Icons.chevron_right)),
            ]),
          ),
      ]),
    );
  }

  Widget _placeholder() => Container(width: 56, height: 56, color: Colors.grey[200],
      child: const Icon(Icons.image, color: Colors.grey, size: 24));
}

// ─── Product Form ────────────────────────────────────────

class _ProductForm extends StatefulWidget {
  final bool isEdit;
  final String? productId;
  final TextEditingController name, brand, price, mrp, stock, description;
  final String category;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _ProductForm({
    required this.isEdit, this.productId,
    required this.name, required this.brand, required this.price, required this.mrp,
    required this.stock, required this.description, required this.category, required this.onSave,
  });

  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  late String _category;
  bool _saving = false;
  final _categories = [
    'Baby Care', 'Bakery & Snacks', 'Beverages', 'Chocolates & Candies', 'Cooking Oils',
    'Dairy & Fats', 'Dry Fruits & Nuts', 'Electronics', 'Health & Nutrition', 'Healthcare',
    'Household', 'Kitchen Accessories', 'Miscellaneous', 'Pasta & Noodles', 'Personal Care',
    'Pooja & Religious', 'Pulses & Grains', 'Ready to Cook', 'Rice & Cereals',
    'Salt & Condiments', 'Spices & Masalas', 'Sweeteners', 'Tea & Coffee',
    'Toys & Stationery', 'Vegetables & Fruits',
  ];

  @override
  void initState() {
    super.initState();
    _category = widget.category.isNotEmpty && _categories.contains(widget.category)
        ? widget.category
        : _categories.first;
  }

  Future<void> _save() async {
    if (widget.name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final data = {
      'name': widget.name.text.trim(),
      'brand': widget.brand.text.trim(),
      'category': _category,
      'price': double.tryParse(widget.price.text) ?? 0,
      'original_price': double.tryParse(widget.mrp.text) ?? 0,
      'stock': int.tryParse(widget.stock.text) ?? 0,
      'description': widget.description.text.trim(),
    };
    if (!widget.isEdit) {
      data['image_url'] = '';
      data['featured'] = false;
      data['sold_count'] = 0;
    }
    await widget.onSave(data);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        Text(widget.isEdit ? 'Edit Product' : 'Add New Product',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),

        _field(widget.name, 'Product Name *', Icons.shopping_bag_outlined),
        const SizedBox(height: 12),
        _field(widget.brand, 'Brand', Icons.business),
        const SizedBox(height: 12),

        DropdownButtonFormField<String>(
          initialValue: _category,
          items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 14)))).toList(),
          onChanged: (v) => setState(() => _category = v!),
          decoration: InputDecoration(
            labelText: 'Category', prefixIcon: const Icon(Icons.category),
            filled: true, fillColor: Colors.grey[50],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.indigo, width: 2)),
          ),
        ),
        const SizedBox(height: 12),

        Row(children: [
          Expanded(child: _field(widget.price, 'Selling Price (₹) *', Icons.currency_rupee, keyboard: TextInputType.number)),
          const SizedBox(width: 12),
          Expanded(child: _field(widget.mrp, 'MRP (₹)', Icons.sell, keyboard: TextInputType.number)),
        ]),
        const SizedBox(height: 12),

        _field(widget.stock, 'Stock Quantity *', Icons.inventory, keyboard: TextInputType.number),
        const SizedBox(height: 12),

        TextField(
          controller: widget.description,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Description', prefixIcon: const Padding(padding: EdgeInsets.only(bottom: 40), child: Icon(Icons.description)),
            filled: true, fillColor: Colors.grey[50],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.indigo, width: 2)),
          ),
        ),
        const SizedBox(height: 24),

        SizedBox(height: 54, child: ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: Icon(_saving ? null : (widget.isEdit ? Icons.save : Icons.add), size: 20),
          label: _saving
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(widget.isEdit ? 'Save Changes' : 'Add Product',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
        )),
      ])),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon, {TextInputType keyboard = TextInputType.text}) {
    return TextField(
      controller: c, keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label, prefixIcon: Icon(icon),
        filled: true, fillColor: Colors.grey[50],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.indigo, width: 2)),
      ),
    );
  }
}
