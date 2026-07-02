import 'package:flutter/material.dart';

class ProductImage extends StatelessWidget {
  final String imageUrl;
  final String? category;
  final String? name;
  final double? width;
  final double? height;
  final BoxFit fit;

  const ProductImage({
    super.key,
    required this.imageUrl,
    this.category,
    this.name,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  // Each category maps to a (soft background, accent) colour pair.
  static const _categoryColors = <String, List<Color>>{
    'fruit': [Color(0xFFE8F5E9), Color(0xFF43A047)],
    'vegetable': [Color(0xFFE8F5E9), Color(0xFF2E7D32)],
    'dairy': [Color(0xFFFFF8E1), Color(0xFFF9A825)],
    'bakery': [Color(0xFFFFF3E0), Color(0xFFEF6C00)],
    'beverage': [Color(0xFFE3F2FD), Color(0xFF1976D2)],
    'snack': [Color(0xFFFCE4EC), Color(0xFFC2185B)],
    'meat': [Color(0xFFFFEBEE), Color(0xFFD32F2F)],
    'frozen': [Color(0xFFE0F7FA), Color(0xFF0097A7)],
    'clean': [Color(0xFFE8EAF6), Color(0xFF3949AB)],
    'personal': [Color(0xFFF3E5F5), Color(0xFF8E24AA)],
    'spice': [Color(0xFFFBE9E7), Color(0xFFE64A19)],
    'rice': [Color(0xFFF1F8E9), Color(0xFF689F38)],
    'oil': [Color(0xFFFFF8E1), Color(0xFFF57F17)],
    'baby': [Color(0xFFFCE4EC), Color(0xFFEC407A)],
  };

  static const _categoryIcons = <String, IconData>{
    'fruit': Icons.apple,
    'vegetable': Icons.eco,
    'dairy': Icons.egg_alt,
    'bakery': Icons.bakery_dining,
    'beverage': Icons.local_cafe,
    'snack': Icons.cookie,
    'meat': Icons.set_meal,
    'frozen': Icons.ac_unit,
    'clean': Icons.cleaning_services,
    'personal': Icons.sanitizer,
    'spice': Icons.local_fire_department,
    'rice': Icons.rice_bowl,
    'oil': Icons.water_drop,
    'baby': Icons.child_friendly,
  };

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) return _placeholder();

    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          width: width,
          height: height,
          color: _bg,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: _accent.withValues(alpha: 0.5)),
            ),
          ),
        );
      },
      errorBuilder: (_, _, _) => _placeholder(),
    );
  }

  List<Color> get _pair {
    if (category != null) {
      final cat = category!.toLowerCase();
      for (final entry in _categoryColors.entries) {
        if (cat.contains(entry.key)) return entry.value;
      }
    }
    return const [Color(0xFFF1F3F6), Color(0xFF1976D2)];
  }

  Color get _bg => _pair[0];
  Color get _accent => _pair[1];

  IconData get _icon {
    if (category != null) {
      final cat = category!.toLowerCase();
      for (final entry in _categoryIcons.entries) {
        if (cat.contains(entry.key)) return entry.value;
      }
    }
    return Icons.shopping_basket;
  }

  /// A clean, branded placeholder for products without a photo — a soft
  /// category-tinted panel with the category icon in a white disc.
  Widget _placeholder() {
    return Container(
      width: width,
      height: height,
      color: _bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.15), blurRadius: 8)],
              ),
              child: Icon(_icon, size: 28, color: _accent),
            ),
            const SizedBox(height: 8),
            Text(
              'Dhanam Stores',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: _accent.withValues(alpha: 0.7), letterSpacing: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}
