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

  // Each category maps to an accent colour + icon. The soft background tint
  // is derived from the accent at render time (see _bg), so every entry
  // automatically gets a matching bg/accent pair without hand-picking two
  // colours per category.
  static const _categoryStyles = <String, (Color, IconData)>{
    'vegetables & fruits': (Color(0xFF43A047), Icons.eco),
    'dairy & fats': (Color(0xFFFBC02D), Icons.egg_alt),
    'bakery & snacks': (Color(0xFFEF6C00), Icons.bakery_dining),
    'beverages': (Color(0xFF1976D2), Icons.local_cafe),
    'chocolates & candies': (Color(0xFF6D4C41), Icons.cake),
    'cooking oils': (Color(0xFF9E9D24), Icons.water_drop),
    'dry fruits & nuts': (Color(0xFFA1887F), Icons.spa),
    'electronics': (Color(0xFF455A64), Icons.devices_other),
    'health & nutrition': (Color(0xFF00897B), Icons.fitness_center),
    'healthcare': (Color(0xFF01579B), Icons.medical_services),
    'household': (Color(0xFF3949AB), Icons.cleaning_services),
    'kitchen accessories': (Color(0xFF7E57C2), Icons.kitchen),
    'miscellaneous': (Color(0xFF757575), Icons.shopping_basket),
    'pasta & noodles': (Color(0xFFFF7043), Icons.ramen_dining),
    'personal care': (Color(0xFF8E24AA), Icons.sanitizer),
    'pooja & religious': (Color(0xFFFFB300), Icons.temple_hindu),
    'pulses & grains': (Color(0xFF689F38), Icons.grain),
    'ready to cook': (Color(0xFFAD1457), Icons.soup_kitchen),
    'rice & cereals': (Color(0xFFC0CA33), Icons.rice_bowl),
    'salt & condiments': (Color(0xFF5E35B1), Icons.grain),
    'spices & masalas': (Color(0xFFD32F2F), Icons.local_fire_department),
    'sweeteners': (Color(0xFFBF8F00), Icons.icecream),
    'tea & coffee': (Color(0xFF3E2723), Icons.local_cafe),
    'toys & stationery': (Color(0xFF26A69A), Icons.toys),
    'baby care': (Color(0xFFEC407A), Icons.child_friendly),
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

  static const _defaultStyle = (Color(0xFF1976D2), Icons.shopping_basket);

  (Color, IconData) get _style {
    if (category == null) return _defaultStyle;
    final cat = category!.trim().toLowerCase();
    final exact = _categoryStyles[cat];
    if (exact != null) return exact;
    // Fall back to a substring match in case the category string varies
    // slightly (extra words, different punctuation, etc).
    for (final entry in _categoryStyles.entries) {
      if (cat.contains(entry.key) || entry.key.contains(cat)) return entry.value;
    }
    return _defaultStyle;
  }

  Color get _accent => _style.$1;
  IconData get _icon => _style.$2;

  // Soft background tint derived from the accent so every category gets a
  // harmonious, guaranteed-matching bg/accent pair.
  Color get _bg => Color.alphaBlend(_accent.withValues(alpha: 0.12), Colors.white);

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
