import 'package:flutter/material.dart';

enum CharacterMood { happy, listening, thinking }

class FriendlyCharacter extends StatefulWidget {
  const FriendlyCharacter({
    super.key,
    required this.mood,
    required this.isListening,
  });

  final CharacterMood mood;
  final bool isListening;

  @override
  State<FriendlyCharacter> createState() => _FriendlyCharacterState();
}

class _FriendlyCharacterState extends State<FriendlyCharacter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathingController;
  late final Animation<double> _breathingScale;

  @override
  void initState() {
    super.initState();
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
    _breathingScale = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(
        parent: _breathingController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _breathingController.dispose();
    super.dispose();
  }

  Color _getCharacterColor() {
    switch (widget.mood) {
      case CharacterMood.listening:
        return const Color(0xFF81C784); // soft green
      case CharacterMood.thinking:
        return const Color(0xFFFFB74D); // soft orange
      case CharacterMood.happy:
        return const Color(0xFF64B5F6); // pastel blue
    }
  }

  Color _getGlowColor() {
    switch (widget.mood) {
      case CharacterMood.listening:
        return const Color(0xFFA5D6A7); // lighter green
      case CharacterMood.thinking:
        return const Color(0xFFFFCA28); // lighter orange
      case CharacterMood.happy:
        return const Color(0xFF90CAF9); // lighter blue
    }
  }

  double _getEyeWidth() {
    switch (widget.mood) {
      case CharacterMood.listening:
        return 22;
      case CharacterMood.thinking:
        return 20;
      case CharacterMood.happy:
        return 28;
    }
  }

  double _getEyeHeight() {
    switch (widget.mood) {
      case CharacterMood.listening:
        return 28;
      case CharacterMood.thinking:
        return 18;
      case CharacterMood.happy:
        return 32;
    }
  }

  bool _shouldShowCheeks() => widget.mood == CharacterMood.happy;

  bool _shouldBreath() => !widget.isListening;

  @override
  Widget build(BuildContext context) {
    final characterColor = _getCharacterColor();
    final glowColor = _getGlowColor();
    final eyeWidth = _getEyeWidth();
    final eyeHeight = _getEyeHeight();
    final breathing = _shouldBreath();

    return AnimatedBuilder(
      animation: _breathingScale,
      builder: (context, child) {
        return Transform.scale(
          scale: breathing ? _breathingScale.value : (widget.isListening ? 1.08 : 1.0),
          child: Container(
            width: 260,
            height: 260,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Background glow
                AnimatedContainer(
                  duration: const Duration(milliseconds: 800),
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        glowColor.withOpacity(0.6),
                        glowColor.withOpacity(0.0),
                      ],
                      stops: const [0.3, 0.7],
                    ),
                  ),
                  transform: Matrix4.identity()
                    ..scale(breathing ? 1.05 : 1.0),
                ),
                // Main face circle
                AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: characterColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
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
                        top: 85,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              width: eyeWidth,
                              height: eyeHeight,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 50),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              width: eyeWidth,
                              height: eyeHeight,
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
                        top: 150,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          width: 90,
                          height: 50,
                          decoration: BoxDecoration(
                            borderRadius: widget.mood == CharacterMood.happy
                                ? const BorderRadius.only(
                                    bottomLeft: Radius.circular(90),
                                    bottomRight: Radius.circular(90),
                                  )
                                : BorderRadius.zero,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      // Cheeks (only when happy)
                      if (_shouldShowCheeks()) ...[
                        Positioned(
                          top: 115,
                          left: 65,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFFFB6C1).withOpacity(0.4),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 115,
                          right: 65,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFFFB6C1).withOpacity(0.4),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

