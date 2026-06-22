import 'package:flutter/material.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onViewAll;

  const SectionHeader({super.key, required this.title, this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (onViewAll != null)
            GestureDetector(
              onTap: onViewAll,
              child: Text('View All', style: TextStyle(fontSize: 14, color: Colors.blue[700], fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}
