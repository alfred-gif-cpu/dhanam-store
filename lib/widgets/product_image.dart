import 'package:flutter/material.dart';

class ProductImage extends StatelessWidget {
  final String imageUrl;
  final String? category;
  final double? width;
  final double? height;
  final BoxFit fit;

  const ProductImage({
    super.key,
    required this.imageUrl,
    this.category,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  static const _categoryColors = <String, Color>{
    'fruit': Color(0xFFE8F5E9),
    'vegetable': Color(0xFFC8E6C9),
    'dairy': Color(0xFFFFF8E1),
    'bakery': Color(0xFFFFF3E0),
    'beverage': Color(0xFFE3F2FD),
    'snack': Color(0xFFFCE4EC),
    'meat': Color(0xFFFFEBEE),
    'frozen': Color(0xFFE0F7FA),
    'clean': Color(0xFFE8EAF6),
    'personal': Color(0xFFF3E5F5),
    'spice': Color(0xFFFBE9E7),
    'rice': Color(0xFFF1F8E9),
    'oil': Color(0xFFFFF8E1),
  };

  static const _categoryIcons = <String, IconData>{
    'fruit': Icons.apple,
    'vegetable': Icons.grass,
    'dairy': Icons.egg,
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
          color: _bgColor,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Color get _bgColor {
    if (category == null) return Colors.grey[200]!;
    final cat = category!.toLowerCase();
    for (final entry in _categoryColors.entries) {
      if (cat.contains(entry.key)) return entry.value;
    }
    return Colors.grey[200]!;
  }

  IconData get _icon {
    if (category == null) return Icons.image_not_supported_outlined;
    final cat = category!.toLowerCase();
    for (final entry in _categoryIcons.entries) {
      if (cat.contains(entry.key)) return entry.value;
    }
    return Icons.shopping_bag_outlined;
  }

  Widget _placeholder() {
    return Container(
      width: width,
      height: height,
      color: _bgColor,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_icon, size: 40, color: Colors.grey[500]),
          const SizedBox(height: 4),
          Text(
            category ?? 'No Image',
            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
