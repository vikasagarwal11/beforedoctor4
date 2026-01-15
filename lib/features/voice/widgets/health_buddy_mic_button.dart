import 'package:flutter/material.dart';

class HealthBuddyMicButton extends StatefulWidget {
  const HealthBuddyMicButton({
    super.key,
    required this.isListening,
    required this.onPressed,
  });

  final bool isListening;
  final VoidCallback onPressed;

  @override
  State<HealthBuddyMicButton> createState() => _HealthBuddyMicButtonState();
}

class _HealthBuddyMicButtonState extends State<HealthBuddyMicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(
        parent: _pressController,
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _pressController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _pressController.reverse();
    widget.onPressed();
  }

  void _handleTapCancel() {
    _pressController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isListening = widget.isListening;
    final gradient = isListening
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEF5350), Color(0xFFE53935)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF66BB6A), Color(0xFF4CAF50)],
          );

    final shadowColor = isListening
        ? const Color(0xFFEF5350).withOpacity(0.4)
        : const Color(0xFF4CAF50).withOpacity(0.35);

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: gradient,
                boxShadow: [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 48,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Icon(
                isListening ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: isListening ? 40 : 44,
              ),
            ),
          );
        },
      ),
    );
  }
}


