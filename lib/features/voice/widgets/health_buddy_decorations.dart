import 'package:flutter/material.dart';
import 'dart:math' as math;

class HealthBuddyDecorations extends StatelessWidget {
  const HealthBuddyDecorations({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Smiley face decoration (top-right)
        _FloatingDecoration(
          top: 40,
          right: 40,
          child: _SmileyFace(),
          duration: const Duration(milliseconds: 6000),
        ),
        // Star decoration (bottom-left)
        _FloatingDecoration(
          bottom: 120,
          left: 32,
          child: _Star(),
          duration: const Duration(milliseconds: 8000),
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
    required this.child,
    required this.duration,
    this.reverse = false,
  });

  final double? top;
  final double? left;
  final double? bottom;
  final double? right;
  final Widget child;
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
    
    _floatAnimation = Tween<double>(begin: 0.0, end: -15.0).animate(
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
              child: Opacity(
                opacity: widget.top != null ? 0.3 : 0.25,
                child: widget.child,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SmileyFace extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Face circle
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF81C784),
            ),
          ),
          // Left eye
          Positioned(
            left: 15,
            top: 20,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ),
          // Right eye
          Positioned(
            right: 15,
            top: 20,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ),
          // Smile
          Positioned(
            bottom: 15,
            child: CustomPaint(
              size: const Size(40, 20),
              painter: _SmileIconPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmileIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(5, 5);
    path.quadraticBezierTo(size.width / 2, size.height, size.width - 5, 5);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Star extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(50, 50),
      painter: _StarPainter(),
    );
  }
}

class _StarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFB74D)
      ..style = PaintingStyle.fill;

    final path = Path();
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final innerRadius = outerRadius * 0.4;
    final numPoints = 5;

    for (int i = 0; i < numPoints * 2; i++) {
      final angle = (i * math.pi) / numPoints - math.pi / 2;
      final radius = i.isEven ? outerRadius : innerRadius;
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


