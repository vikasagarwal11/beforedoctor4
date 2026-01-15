import 'package:flutter/material.dart';
import 'dart:math' as math;

class TeddyBearCharacter extends StatefulWidget {
  const TeddyBearCharacter({
    super.key,
    required this.isListening,
  });

  final bool isListening;

  @override
  State<TeddyBearCharacter> createState() => _TeddyBearCharacterState();
}

class _TeddyBearCharacterState extends State<TeddyBearCharacter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathingController;
  late final Animation<double> _breathingScale;

  @override
  void initState() {
    super.initState();
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
    _breathingScale = Tween<double>(begin: 1.0, end: 1.05).animate(
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

  @override
  Widget build(BuildContext context) {
    final isListening = widget.isListening;

    return AnimatedBuilder(
      animation: _breathingScale,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.isListening ? 1.08 : _breathingScale.value,
          child: SizedBox(
            width: 280,
            height: 280,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Main teddy bear body
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFB6C1), // Light pink
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFB6C1).withOpacity(0.4),
                        blurRadius: 40,
                        offset: const Offset(0, 20),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Ears
                      Positioned(
                        top: 20,
                        left: 10,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFFFC1CC), // Lighter pink
                          ),
                        ),
                      ),
                      Positioned(
                        top: 20,
                        right: 10,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFFFC1CC),
                          ),
                        ),
                      ),
                      // Eyes
                      Positioned(
                        top: 70,
                        left: 65,
                        child: Container(
                          width: isListening ? 14 : 18,
                          height: isListening ? 14 : 18,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 70,
                        right: 65,
                        child: Container(
                          width: isListening ? 14 : 18,
                          height: isListening ? 14 : 18,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      // Snout
                      Positioned(
                        top: 100,
                        child: Container(
                          width: 50,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFFFE4E8), // Very light pink
                            border: Border.all(
                              color: const Color(0xFFFFB6C1),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      // Mouth
                      if (isListening)
                        Positioned(
                          top: 130,
                          child: Container(
                            width: 30,
                            height: 8,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: const Color(0xFFEC407A), // Pink
                            ),
                          ),
                        )
                      else
                        Positioned(
                          top: 130,
                          child: CustomPaint(
                            size: const Size(30, 15),
                            painter: _SmilePainter(),
                          ),
                        ),
                    ],
                  ),
                ),
                // Stethoscope
                Positioned(
                  top: 40,
                  child: CustomPaint(
                    size: const Size(200, 120),
                    painter: _StethoscopePainter(),
                  ),
                ),
                // Sound waves when listening
                if (isListening) ...[
                  Positioned(
                    top: 60,
                    left: 40,
                    child: _SoundWave(delay: 0),
                  ),
                  Positioned(
                    top: 60,
                    right: 40,
                    child: _SoundWave(delay: 0.3),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SmilePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFEC407A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(5, size.height / 2);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width - 5,
      size.height / 2,
    );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StethoscopePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFEC407A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    // Left earpiece
    canvas.drawLine(
      const Offset(30, 0),
      const Offset(40, 20),
      paint,
    );
    canvas.drawCircle(const Offset(35, 5), 6, Paint()..color = const Color(0xFFEC407A)..style = PaintingStyle.fill);

    // Right earpiece
    canvas.drawLine(
      Offset(size.width - 30, 0),
      Offset(size.width - 40, 20),
      paint,
    );
    canvas.drawCircle(Offset(size.width - 35, 5), 6, Paint()..color = const Color(0xFFEC407A)..style = PaintingStyle.fill);

    // Tube going down
    final path = Path();
    path.moveTo(size.width / 2, 25);
    path.quadraticBezierTo(
      size.width / 2,
      60,
      size.width / 2 - 15,
      80,
    );
    canvas.drawPath(path, paint);

    // Chest piece
    canvas.drawCircle(
      Offset(size.width / 2 - 15, 90),
      12,
      Paint()
        ..color = const Color(0xFFEC407A)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(size.width / 2 - 15, 90),
      12,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SoundWave extends StatefulWidget {
  const _SoundWave({required this.delay});

  final double delay;

  @override
  State<_SoundWave> createState() => _SoundWaveState();
}

class _SoundWaveState extends State<_SoundWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
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
            scale: 0.8 + (_animation.value * 0.5),
            child: CustomPaint(
              size: const Size(30, 30),
              painter: _WavePainter(),
            ),
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFEC407A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (int i = 0; i < 3; i++) {
      final radius = 8.0 + (i * 8.0);
      canvas.drawArc(
        Rect.fromCircle(
          center: Offset(size.width / 2, size.height / 2),
          radius: radius,
        ),
        math.pi * 0.3,
        math.pi * 0.4,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


