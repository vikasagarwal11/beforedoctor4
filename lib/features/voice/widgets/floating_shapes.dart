import 'package:flutter/material.dart';

class FloatingShapes extends StatelessWidget {
  const FloatingShapes({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Top left floating shape
        _FloatingShape(
          top: 80,
          left: 60,
          width: 140,
          height: 140,
          color: const Color(0xFFFFF59D).withOpacity(0.18),
          blur: 40,
          duration: const Duration(milliseconds: 12000),
        ),
        // Bottom right floating shape
        _FloatingShape(
          bottom: 160,
          right: 48,
          width: 180,
          height: 180,
          color: const Color(0xFFD1FAE5).withOpacity(0.22),
          blur: 50,
          duration: const Duration(milliseconds: 15000),
          reverse: true,
        ),
      ],
    );
  }
}

class _FloatingShape extends StatefulWidget {
  const _FloatingShape({
    this.top,
    this.left,
    this.bottom,
    this.right,
    required this.width,
    required this.height,
    required this.color,
    required this.blur,
    required this.duration,
    this.reverse = false,
  });

  final double? top;
  final double? left;
  final double? bottom;
  final double? right;
  final double width;
  final double height;
  final Color color;
  final double blur;
  final Duration duration;
  final bool reverse;

  @override
  State<_FloatingShape> createState() => _FloatingShapeState();
}

class _FloatingShapeState extends State<_FloatingShape>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat(reverse: widget.reverse);
    _animation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -0.08),
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: widget.top,
      left: widget.left,
      bottom: widget.bottom,
      right: widget.right,
      child: SlideTransition(
        position: _animation,
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

