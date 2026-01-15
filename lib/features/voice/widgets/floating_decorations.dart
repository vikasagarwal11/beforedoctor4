import 'package:flutter/material.dart';
import 'dart:math' as math;

class FloatingDecorations extends StatelessWidget {
  const FloatingDecorations({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Floating heart 1 (top-left)
        _FloatingDecoration(
          top: 60,
          left: 40,
          emoji: '💕',
          duration: const Duration(milliseconds: 3000),
        ),
        // Floating sparkle 1 (top-right)
        _FloatingDecoration(
          top: 80,
          right: 50,
          emoji: '✨',
          duration: const Duration(milliseconds: 3500),
          reverse: true,
        ),
        // Floating flower 1 (middle-left)
        _FloatingDecoration(
          top: 300,
          left: 30,
          emoji: '🌸',
          duration: const Duration(milliseconds: 4000),
        ),
        // Floating heart 2 (middle-right)
        _FloatingDecoration(
          top: 250,
          right: 40,
          emoji: '💕',
          duration: const Duration(milliseconds: 3200),
          reverse: true,
        ),
        // Floating sparkle 2 (bottom-left)
        _FloatingDecoration(
          bottom: 200,
          left: 50,
          emoji: '✨',
          duration: const Duration(milliseconds: 3800),
        ),
        // Floating flower 2 (bottom-right)
        _FloatingDecoration(
          bottom: 250,
          right: 30,
          emoji: '🌸',
          duration: const Duration(milliseconds: 3600),
          reverse: true,
        ),
      ],
    );
  }
}

class _FloatingDecoration extends StatefulWidget {
  const _FloatingDecoration({
    this.top,
    this.left,
    this.bottom,
    this.right,
    required this.emoji,
    required this.duration,
    this.reverse = false,
  });

  final double? top;
  final double? left;
  final double? bottom;
  final double? right;
  final String emoji;
  final Duration duration;
  final bool reverse;

  @override
  State<_FloatingDecoration> createState() => _FloatingDecorationState();
}

class _FloatingDecorationState extends State<_FloatingDecoration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _floatAnimation;
  late final Animation<double> _rotateAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat(reverse: widget.reverse);
    
    _floatAnimation = Tween<double>(begin: 0.0, end: -25.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
    
    _rotateAnimation = Tween<double>(begin: 0.0, end: 5.0 * math.pi / 180).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
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
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, _floatAnimation.value),
            child: Transform.rotate(
              angle: _rotateAnimation.value,
              child: Text(
                widget.emoji,
                style: const TextStyle(
                  fontSize: 32,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}


