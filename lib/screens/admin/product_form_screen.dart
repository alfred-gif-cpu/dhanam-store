import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../services/admin_service.dart';
import '../../services/api_service.dart';
import '../../models/category.dart';

class ProductFormScreen extends StatefulWidget {
  final Product? product;
  const ProductFormScreen({super.key, this.product});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final AdminService _admin = AdminService();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  List<Category> _categories = [];

  late TextEditingController _name, _brand, _price, _originalPrice, _stock, _description;
  String _category = '';

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p?.name ?? '');
    _brand = TextEditingController(text: p?.brand ?? '');
    _price = TextEditingController(text: p != null ? p.price.toStringAsFixed(0) : '');
    _originalPrice = TextEditingController(text: p != null && p.originalPrice > p.price ? p.originalPrice.toStringAsFixed(0) : '');
    _stock = TextEditingController(text: p?.stock.toString() ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _category = p?.category ?? '';
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await ApiService().getCategories();
      setState(() => _categories = cats);
      if (_category.isEmpty && cats.isNotEmpty) _category = cats.first.name;
    } catch (_) {}
  }

  @override
  void dispose() {
    _name.dispose(); _brand.dispose(); _price.dispose();
    _originalPrice.dispose(); _stock.dispose(); _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = {
        'name': _name.text.trim(),
        'brand': _brand.text.trim(),
        'category': _category,
        'price': double.tryParse(_price.text) ?? 0,
        'original_price': double.tryParse(_originalPrice.text) ?? 0,
        'stock': int.tryParse(_stock.text) ?? 0,
        'description': _description.text.trim(),
        'image_url': '',
        'featured': false,
        'sold_count': 0,
      };
      if (_isEditing) {
        data.remove('image_url');
        data.remove('featured');
        data.remove('sold_count');
        await _admin.updateProduct(widget.product!.id, data);
      } else {
        final result = await _admin.createProduct(data);
        if (result['status'] != 'created') throw Exception('Insert failed');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isEditing ? 'Product updated' : 'Product created'),
          backgroundColor: Colors.blue, behavior: SnackBarBehavior.floating));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Product' : 'Add Product'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _card([
            _field(_name, 'Product Name', required: true),
            const SizedBox(height: 14),
            _field(_brand, 'Brand'),
            const SizedBox(height: 14),
            // Category dropdown
            DropdownButtonFormField<String>(
              initialValue: _categories.any((c) => c.name == _category) ? _category : null,
              items: _categories.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(),
              onChanged: (v) => _category = v ?? '',
              decoration: _decoration('Category'),
            ),
          ]),
          const SizedBox(height: 12),
          _card([
            Row(children: [
              Expanded(child: _field(_price, 'Price (₹)', keyboard: TextInputType.number, required: true)),
              const SizedBox(width: 12),
              Expanded(child: _field(_originalPrice, 'MRP / Original', keyboard: TextInputType.number)),
            ]),
            const SizedBox(height: 14),
            _field(_stock, 'Stock Quantity', keyboard: TextInputType.number, required: true),
          ]),
          const SizedBox(height: 12),
          _card([
            TextFormField(
              controller: _description,
              maxLines: 4,
              decoration: _decoration('Description'),
            ),
          ]),
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
              child: _saving
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_isEditing ? 'Update Product' : 'Create Product',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  Widget _field(TextEditingController controller, String label,
      {bool required = false, TextInputType keyboard = TextInputType.text}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
      decoration: _decoration(label),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.grey[50],
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.indigo, width: 2)),
  );
}
