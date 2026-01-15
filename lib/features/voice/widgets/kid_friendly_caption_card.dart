import 'package:flutter/material.dart';

class KidFriendlyCaptionCard extends StatelessWidget {
  const KidFriendlyCaptionCard({
    super.key,
    required this.caption,
    required this.isListening,
  });

  final String caption;
  final bool isListening;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 540),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: Colors.white.withOpacity(0.7),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 48,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 40, 28, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Caption text with animation
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.06),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Text(
                    caption,
                    key: ValueKey(caption),
                    style: const TextStyle(
                      fontSize: 24,
                      height: 1.45,
                      color: Color(0xFF1A3C34),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Typing dots when listening
                if (isListening)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _TypingDots(),
                  ),
              ],
            ),
          ),
          // CC Badge positioned absolutely
          Positioned(
            top: -12,
            right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Text(
                'CC',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
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
        const SizedBox(width: 8),
        _BouncingDot(delay: 0.2, controller: _controller),
        const SizedBox(width: 8),
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
            ? (animationValue < 0.4 ? -animationValue * 25 : 0.0)
            : 0.0;
        return Transform.translate(
          offset: Offset(0, offset),
          child: Container(
            width: 10,
            height: 10,
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

