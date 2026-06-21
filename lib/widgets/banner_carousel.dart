import 'dart:async';
import 'package:flutter/material.dart';
import '../models/banner.dart';

class BannerCarousel extends StatefulWidget {
  final List<HomeBanner> banners;
  const BannerCarousel({super.key, required this.banners});

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  final PageController _controller = PageController();
  int _current = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.banners.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        final next = (_current + 1) % widget.banners.length;
        _controller.animateToPage(next, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.banners.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        SizedBox(
          height: 160,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.banners.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (context, index) {
              final banner = widget.banners[index];
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.green[50],
                ),
                clipBehavior: Clip.antiAlias,
                child: banner.image.isNotEmpty
                    ? Image.network(banner.image, fit: BoxFit.cover, width: double.infinity,
                        errorBuilder: (_, __, ___) => _placeholder(banner.title))
                    : _placeholder(banner.title),
              );
            },
          ),
        ),
        if (widget.banners.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.banners.length, (i) => Container(
                width: _current == i ? 20 : 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: _current == i ? Colors.green : Colors.grey[300],
                ),
              )),
            ),
          ),
      ],
    );
  }

  Widget _placeholder(String title) {
    return Container(
      color: Colors.green[100],
      child: Center(child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green[800]))),
    );
  }
}
