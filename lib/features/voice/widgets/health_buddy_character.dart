import 'package:flutter/material.dart';

enum HealthBuddyState { happy, listening, thinking }

class HealthBuddyCharacter extends StatefulWidget {
  const HealthBuddyCharacter({
    super.key,
    required this.state,
    required this.isListening,
  });

  final HealthBuddyState state;
  final bool isListening;

  @override
  State<HealthBuddyCharacter> createState() => _HealthBuddyCharacterState();
}

class _HealthBuddyCharacterState extends State<HealthBuddyCharacter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color _getCharacterColor() {
    switch (widget.state) {
      case HealthBuddyState.listening:
        return const Color(0xFF81C784); // Green
      case HealthBuddyState.thinking:
        return const Color(0xFFFFB74D); // Orange
      case HealthBuddyState.happy:
        return const Color(0xFF64B5F6); // Blue
    }
  }

  Color _getGradientEndColor() {
    switch (widget.state) {
      case HealthBuddyState.listening:
        return const Color(0xFF66BB6A);
      case HealthBuddyState.thinking:
        return const Color(0xFFFFA726);
      case HealthBuddyState.happy:
        return const Color(0xFF42A5F5);
    }
  }

  double _getEyeSize() {
    return widget.state == HealthBuddyState.listening ? 12 : 18;
  }

  @override
  Widget build(BuildContext context) {
    final characterColor = _getCharacterColor();
    final gradientEndColor = _getGradientEndColor();
    final eyeSize = _getEyeSize();
    final isListening = widget.isListening;

    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pulse ring when listening
          if (isListening)
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF81C784).withOpacity(0.4),
                        width: 4,
                      ),
                    ),
                    transform: Matrix4.identity()
                      ..scale(_pulseAnimation.value),
                  ),
                );
              },
            ),
          // Main character circle
          Transform.scale(
            scale: isListening ? 1.05 : 1.0,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [characterColor, gradientEndColor],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 60,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Eyes
                  Positioned(
                    top: 77,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: eyeSize,
                          height: eyeSize,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 45),
                        Container(
                          width: eyeSize,
                          height: eyeSize,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Mouth
                  Positioned(
                    top: 121,
                    child: SizedBox(
                      width: 80,
                      height: 40,
                      child: isListening
                          ? Container(
                              width: 24,
                              height: 32,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.white,
                              ),
                            )
                          : CustomPaint(
                              size: const Size(80, 40),
                              painter: _SmilePainter(),
                            ),
                    ),
                  ),
                  // Sound waves when listening
                  if (isListening) ...[
                    Positioned(
                      top: 110,
                      left: 20,
                      child: _SoundWaveBar(delay: 0),
                    ),
                    Positioned(
                      top: 110,
                      right: 20,
                      child: _SoundWaveBar(delay: 0.5),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmilePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(15, 15);
    path.quadraticBezierTo(40, 30, 65, 15);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SoundWaveBar extends StatefulWidget {
  const _SoundWaveBar({required this.delay});

  final double delay;

  @override
  State<_SoundWaveBar> createState() => _SoundWaveBarState();
}

class _SoundWaveBarState extends State<_SoundWaveBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
    _controller.forward(from: widget.delay);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Transform.scale(
            scaleX: 0.7 + (_animation.value * 0.5),
            child: Container(
              width: 15,
              height: 3,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      },
    );
  }
}

