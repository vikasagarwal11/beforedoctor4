import 'package:flutter/material.dart';

class TeddyMicButton extends StatefulWidget {
  const TeddyMicButton({
    super.key,
    required this.isListening,
    required this.onPressed,
  });

  final bool isListening;
  final VoidCallback onPressed;

  @override
  State<TeddyMicButton> createState() => _TeddyMicButtonState();
}

class _TeddyMicButtonState extends State<TeddyMicButton>
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
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
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
    final color = isListening ? const Color(0xFFE53935) : const Color(0xFFEC407A);

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: widget.isListening ? 1.1 : _scaleAnimation.value,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: 50,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: Icon(
                isListening ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: isListening ? 56 : 60,
              ),
            ),
          );
        },
      ),
    );
  }
}


