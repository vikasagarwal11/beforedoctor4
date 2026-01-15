import 'package:flutter/material.dart';

class HealthBuddyCaptionCard extends StatelessWidget {
  const HealthBuddyCaptionCard({
    super.key,
    required this.caption,
    required this.isListening,
    required this.captionIndex,
  });

  final String caption;
  final bool isListening;
  final int captionIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 500),
      margin: const EdgeInsets.only(bottom: 30),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.8),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // "Live Captions" label
                Text(
                  'LIVE CAPTIONS',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                // Caption text
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                  child: Text(
                    caption,
                    key: ValueKey(caption),
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.5,
                      color: Color(0xFF2C3E50),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Typing indicator when listening
                if (isListening && captionIndex > 0) _TypingDots(),
              ],
            ),
          ),
          // CC Badge (black)
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Text(
                'CC',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BouncingDot(delay: 0, controller: _controller),
        const SizedBox(width: 4),
        _BouncingDot(delay: 0.2, controller: _controller),
        const SizedBox(width: 4),
        _BouncingDot(delay: 0.4, controller: _controller),
      ],
    );
  }
}

class _BouncingDot extends StatelessWidget {
  const _BouncingDot({
    required this.delay,
    required this.controller,
  });

  final double delay;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final animationValue = (controller.value + delay) % 1.0;
        final offset = (animationValue < 0.8)
            ? (animationValue < 0.4 ? -animationValue * 8 : 0.0)
            : 0.0;
        return Transform.translate(
          offset: Offset(0, offset),
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF81C784),
            ),
          ),
        );
      },
    );
  }
}


