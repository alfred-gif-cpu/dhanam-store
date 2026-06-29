import 'package:flutter/material.dart';
import '../models/category.dart';

class CategoryCarousel extends StatelessWidget {
  final List<Category> categories;
  final ValueChanged<String> onTap;

  const CategoryCarousel({super.key, required this.categories, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final cat = categories[index];
          return GestureDetector(
            onTap: () => onTap(cat.name),
            child: SizedBox(
              width: 76,
              child: Column(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: cat.image.isNotEmpty
                        ? Image.network(cat.image, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _fallbackIcon(cat.name))
                        : _fallbackIcon(cat.name),
                  ),
                  const SizedBox(height: 6),
                  Text(cat.name, textAlign: TextAlign.center, maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _fallbackIcon(String name) {
    return Center(child: Icon(Icons.category, size: 28, color: Colors.blue[700]));
  }
}
