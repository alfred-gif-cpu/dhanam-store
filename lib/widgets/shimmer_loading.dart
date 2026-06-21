import 'package:flutter/material.dart';

class ShimmerLoading extends StatefulWidget {
  const ShimmerLoading({super.key});

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _shimmerBox(height: 160, radius: 16),
            const SizedBox(height: 20),
            _shimmerBox(height: 20, width: 140),
            const SizedBox(height: 12),
            SizedBox(
              height: 80,
              child: Row(children: List.generate(5, (i) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 4 ? 10 : 0),
                  child: Column(children: [
                    _shimmerBox(height: 52, width: 52, radius: 14),
                    const SizedBox(height: 6),
                    _shimmerBox(height: 10, width: 44),
                  ]),
                ),
              ))),
            ),
            const SizedBox(height: 20),
            _shimmerBox(height: 20, width: 160),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: Row(children: List.generate(3, (i) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 2 ? 10 : 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _shimmerBox(height: 120, radius: 12),
                    const SizedBox(height: 6),
                    _shimmerBox(height: 12, width: 80),
                    const SizedBox(height: 4),
                    _shimmerBox(height: 14, width: 50),
                  ]),
                ),
              ))),
            ),
            const SizedBox(height: 20),
            _shimmerBox(height: 20, width: 180),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: Row(children: List.generate(3, (i) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 2 ? 10 : 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _shimmerBox(height: 120, radius: 12),
                    const SizedBox(height: 6),
                    _shimmerBox(height: 12, width: 90),
                    const SizedBox(height: 4),
                    _shimmerBox(height: 14, width: 60),
                  ]),
                ),
              ))),
            ),
          ],
        );
      },
    );
  }

  Widget _shimmerBox({required double height, double? width, double radius = 8}) {
    final value = _controller.value;
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment(-1.0 + 2.0 * value, 0),
          end: Alignment(-1.0 + 2.0 * value + 1.0, 0),
          colors: [Colors.grey[200]!, Colors.grey[100]!, Colors.grey[200]!],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}
